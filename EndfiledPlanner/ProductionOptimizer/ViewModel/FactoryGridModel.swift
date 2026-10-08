//
//  FactoryGridModel.swift
//  EndfiledPlanner
//
//  Created by Jinjia Ou on 4/3/26.
//

import Foundation

// MARK: - 布局快照（用于序列化）
struct FactoryLayout: Codable {
    /// 存档数据版本：1 = 配方按列表下标、取货材料按中文名存（旧 recipes.txt 时代）；2 = 配方 ID + itemId
    static let currentDataVersion = 2

    var buildings: [PlacedBuilding]
    var beltNetwork: BeltNetwork
    var savedAt: Date
    var mapType: MapType
    var dataVersion: Int

    static let empty = FactoryLayout(buildings: [], beltNetwork: BeltNetwork(), savedAt: .now, mapType: .valley4)

    init(buildings: [PlacedBuilding], beltNetwork: BeltNetwork, savedAt: Date, mapType: MapType) {
        self.buildings = buildings
        self.beltNetwork = beltNetwork
        self.savedAt = savedAt
        self.mapType = mapType
        self.dataVersion = FactoryLayout.currentDataVersion
    }

    private enum CodingKeys: String, CodingKey {
        case buildings, beltNetwork, savedAt, mapType, dataVersion
    }

    // 旧存档没有 mapType 字段，缺省当四号谷地处理，不然老存档会直接读取失败被清空。
    // 旧版本的配方下标在 PlacedBuilding 解码时就已经迁移成配方 ID，读完即是当前版本
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        buildings = try c.decode([PlacedBuilding].self, forKey: .buildings)
        beltNetwork = try c.decode(BeltNetwork.self, forKey: .beltNetwork)
        savedAt = try c.decode(Date.self, forKey: .savedAt)
        mapType = try c.decodeIfPresent(MapType.self, forKey: .mapType) ?? .valley4
        let stored = try c.decodeIfPresent(Int.self, forKey: .dataVersion) ?? 1
        if stored < FactoryLayout.currentDataVersion {
            print("存档从数据版本 \(stored) 迁移到 \(FactoryLayout.currentDataVersion)")
        }
        dataVersion = FactoryLayout.currentDataVersion
    }
}

// MARK: - 旧存档迁移：配方列表下标 → 配方 ID
/// legacy_recipe_index.json 由 Tools/gen_legacy_recipe_index.py 按旧 recipes.txt 的排序规则一次性生成，
/// 键是建筑 id，数组下标就是旧存档里的 selectedRecipeIndex。
/// 拆解机、精炼炉里第一个产物同名的几条配方，旧版本身每次启动顺序就可能不同，这几条只能尽量对上
enum LegacyRecipeIndex {
    private static let table: [String: [String?]] = {
        guard let url = Bundle.main.url(forResource: "legacy_recipe_index", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let table = try? JSONDecoder().decode([String: [String?]].self, from: data)
        else {
            print("未找到 legacy_recipe_index.json，旧存档的配方选择无法迁移")
            return [:]
        }
        return table
    }()

    static func recipeID(machineID: String, index: Int) -> String? {
        guard let list = table[machineID], list.indices.contains(index) else { return nil }
        return list[index]
    }
}

// MARK: - 网格模型
class FactoryGridModel {

    // MARK: - 保存/读取（UserDefaults）
    private static let saveKey = "factory_layout_v1"

    static func save(_ layout: FactoryLayout) {
        if let data = try? JSONEncoder().encode(layout) {
            UserDefaults.standard.set(data, forKey: saveKey)
        }
    }

    static func load() -> FactoryLayout {
        guard let data = UserDefaults.standard.data(forKey: saveKey),
              let layout = try? JSONDecoder().decode(FactoryLayout.self, from: data)
        else { return .empty }
        return layout
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: saveKey)
    }

    // MARK: - 协议核心：每张地图必有且只有一个，没有就在默认位置（网格正中心）自动生成
    static func defaultProtocolCoreOrigin(on map: MapType) -> GridPoint {
        guard let def = BuildingDefinition.find(BuildingDefinition.protocolCoreID) else { return GridPoint(col: 0, row: 0) }
        let rules = map.rules
        return GridPoint(col: (rules.gridCols - def.size.width) / 2, row: (rules.gridRows - def.size.height) / 2)
    }

    /// 优先放网格正中心；测试产线这种摆得比较满的布局中心可能被占了，
    /// 那就从左上角逐格扫描找第一个能放的位置，尽量不让协议核心直接消失
    static func ensureProtocolCore(in layout: inout FactoryLayout) {
        guard !layout.buildings.contains(where: { $0.definitionID == BuildingDefinition.protocolCoreID }) else { return }
        guard let def = BuildingDefinition.find(BuildingDefinition.protocolCoreID) else { return }

        let center = defaultProtocolCoreOrigin(on: layout.mapType)
        let rules = layout.mapType.rules
        if canPlace(definition: def, at: center, rotation: .up, existing: layout.buildings, mapType: layout.mapType) {
            layout.buildings.append(PlacedBuilding(definitionID: def.id, origin: center, rotation: .up))
            return
        }
        for row in 0...(rules.gridRows - def.size.height) {
            for col in 0...(rules.gridCols - def.size.width) {
                let origin = GridPoint(col: col, row: row)
                if canPlace(definition: def, at: origin, rotation: .up, existing: layout.buildings, mapType: layout.mapType) {
                    layout.buildings.append(PlacedBuilding(definitionID: def.id, origin: origin, rotation: .up))
                    return
                }
            }
        }
        print("协议核心整张图都放不下，需要手动检查布局密度")
    }

    // MARK: - 碰撞检测
    /// 检查新建筑是否与已有建筑重叠，并且符合当前地图的专属放置规则
    static func canPlace(
        definition: BuildingDefinition,
        at origin: GridPoint,
        rotation: BuildingRotation,
        existing: [PlacedBuilding],
        mapType: MapType
    ) -> Bool {
        let rules = mapType.rules
        // 这个建筑本来就不允许出现在当前地图（比如武陵专属建筑在四号谷地）
        guard rules.allows(definition) else { return false }

        // 协议核心全局唯一：已经有一个了就不能再放第二个（重定位时 existing 会把它自己排除掉，不受影响）
        if definition.isProtocolCore, existing.contains(where: { $0.definitionID == definition.id }) {
            return false
        }

        let dummy = PlacedBuilding(definitionID: definition.id, origin: origin, rotation: rotation)
        let newCellsArr = dummy.occupiedCells(definition: definition)
        let newCells = Set(newCellsArr.map { "\($0.col),\($0.row)" })

        // 边界检查
        let size = dummy.effectiveSize(definition: definition)
        if origin.col < 0 || origin.row < 0 { return false }
        if origin.col + size.width > rules.gridCols { return false }
        if origin.row + size.height > rules.gridRows { return false }

        // 碰撞检查
        for placed in existing {
            guard let def = BuildingDefinition.find(placed.definitionID) else { continue }
            let occupiedCells = Set(placed.occupiedCells(definition: def).map { "\($0.col),\($0.row)" })
            if !newCells.isDisjoint(with: occupiedCells) { return false }
        }

        // 仓库存取线基段：必须连着一个源桩才能放（武陵专属，四号谷地放不了这个建筑，
        // isAvailable 那关已经挡掉了，这里只处理武陵）
        if definition.id == BuildingDefinition.warehouseBaseSegmentID {
            let sources = existing.filter { $0.definitionID == BuildingDefinition.warehouseSourceID }
            guard !sources.isEmpty, isConnected(cells: newCellsArr, to: sources, within: wulingConnectRange)
            else { return false }
        }

        // 仓库取货口/存货口的地图专属规则
        if BuildingDefinition.warehousePortIDs.contains(definition.id) {
            switch rules.warehouseLine {
            case .perimeter(let edges):
                guard isFlushOnPerimeter(placed: dummy, definition: definition, edges: edges) else { return false }
            case .busDock:
                // 取货口/存货口可以直接贴源桩，也可以贴基段，两个都算数。
                // 跟四号谷地贴地图边一样，这里也要求长边整条贴死，不是"离得近就行"
                let dockTargets = existing.filter {
                    $0.definitionID == BuildingDefinition.warehouseBaseSegmentID ||
                    $0.definitionID == BuildingDefinition.warehouseSourceID
                }
                guard isDocked(placed: dummy, definition: definition, against: dockTargets) else { return false }
            }
        }

        return true
    }

    // MARK: - 仓库取线的地图专属规则
    // 范围/边的取舍都是先给个合理默认值，后面可以按实际地图再调

    /// 仓库取货口/存货口是长条形（比如 3x1），必须长边整条贴死在允许的那条边上。
    /// 关键点：口要朝地图内部开（贴上边→朝下，贴左边→朝右），不是朝边界外——
    /// 朝外的话外面连接格会落在网格范围之外，传送带根本没地方接。
    /// 四号谷地只允许上边和左边这两条边（绕基地半圈），允许哪几条边见 MapRules
    static func isFlushOnPerimeter(placed: PlacedBuilding, definition: BuildingDefinition, edges: Set<BuildingRotation>) -> Bool {
        guard let port = definition.ports.first else { return false }
        let (portCell, facing) = port.resolvedPosition(placed: placed, definition: definition)
        if edges.contains(.up) && facing == .down && portCell.row == 0 { return true }
        if edges.contains(.left) && facing == .right && portCell.col == 0 { return true }
        return false
    }

    /// 武陵：取货口/存货口贴基段的道理和贴地图边一样——建筑本身只有 1 格厚，
    /// 口朝外面开（对着基段的反方向）没用，得贴着基段、口朝反方向的外面开，
    /// 所以看"端口背后那一格"（朝向的反方向）是不是正好落在基段的占地里
    static func isDocked(placed: PlacedBuilding, definition: BuildingDefinition, against targets: [PlacedBuilding]) -> Bool {
        guard let port = definition.ports.first else { return false }
        let (portCell, facing) = port.resolvedPosition(placed: placed, definition: definition)
        let backCell = GridPoint(col: portCell.col - facing.outputOffset.col,
                                 row: portCell.row - facing.outputOffset.row)
        for target in targets {
            guard let def = BuildingDefinition.find(target.definitionID) else { continue }
            if target.occupiedCells(definition: def).contains(backCell) { return true }
        }
        return false
    }

    /// 仓库存取线基段连源桩：不做寻路，只判断格子距离，
    /// 基段体积比较大，不要求贴死，占的格子只要有一个落在源桩外扩 N 格范围内就算连上
    static let wulingConnectRange = 6

    static func isConnected(cells: [GridPoint], to targets: [PlacedBuilding], within range: Int) -> Bool {
        for target in targets {
            guard let def = BuildingDefinition.find(target.definitionID) else { continue }
            let targetCells = target.occupiedCells(definition: def)
            for c in cells {
                for tc in targetCells {
                    if abs(c.col - tc.col) + abs(c.row - tc.row) <= range {
                        return true
                    }
                }
            }
        }
        return false
    }

    // MARK: - 产线分析
    struct ProductionStats {
        let totalPower: Double          // 净功率 = 耗电合计 − 发电合计 (MW)，负数表示净发电
        let totalPowerConsumed: Double  // 耗电合计 (MW)
        let totalPowerGenerated: Double // 发电合计 (MW)：协议核心固定 200 + 各热能池按实际燃料算
        let hubPower: Double            // 其中协议核心的部分
        let generators: [FlowSimulator.GeneratorState]
        let unpoweredIDs: Set<UUID>     // 需要供电但不在供电桩范围内的建筑（不运行，也不计入耗电）
        let beltFlows: [UUID: FlowSimulator.BeltFlow]
        var unpoweredCount: Int { unpoweredIDs.count }
        var powerShortage: Double { max(0, totalPowerConsumed - totalPowerGenerated) }
        let buildingCount: Int
        let categoryBreakdown: [BuildingCategory: Int]
        let bottleneck: String?         // 瓶颈建筑（节流系数最低的那台）
        let productionLines: [ProductionLine]
        /// 消耗汇总：机器吃掉的原料（含激活/散布用的气体液体）+ 废水处理机处理掉的废液；存货口是入库，不算
        let consumptionLines: [ProductionLine]
        let passthroughCount: Int       // 分流器/汇流器/物流桥这类直通节点数量（不产不耗，不算进产线）
        let outletMaterials: [String]   // 每个取线出口当前设置的材料（未设置显示"未设置"）
        let machineStates: [FlowSimulator.MachineState]
        let sinkStates: [FlowSimulator.SinkState]
        let flowConverged: Bool
        /// 跟当前地图冲突的建筑 → 原因（红框显示，不参与模拟）
        var mapConflicts: [UUID: String] = [:]
    }

    struct ProductionLine {
        let output: String
        let ratePerMin: Double
        let buildingNames: [String]
    }

    /// 某台建筑可选的配方（machineRecipes 按建筑 id 分组）
    static func recipes(for def: BuildingDefinition, in machineRecipes: [String: [Recipe]]) -> [Recipe] {
        machineRecipes[def.id] ?? []
    }

    /// - Parameter machineRecipes: 按建筑 id 分组的配方表（RecipeViewModel.recipesByMachine()）
    static func analyze(layout original: FactoryLayout, machineRecipes: [String: [Recipe]]) -> ProductionStats {
        // 跟地图冲突的建筑不参与模拟、不耗电，跟关掉的建筑一样
        let conflicts = mapConflicts(in: original, machineRecipes: machineRecipes)
        var layout = original
        for i in layout.buildings.indices where conflicts[layout.buildings[i].id] != nil {
            layout.buildings[i].isActive = false
        }
        // 不能用管道的地图上（旧存档里）画着的管道不参与模拟
        if !layout.mapType.rules.allowsPipes {
            layout.beltNetwork.belts.removeAll { $0.lineType == .pipe }
        }
        var totalPowerConsumed = 0.0
        var totalPowerGenerated = 0.0
        var categoryBreakdown: [BuildingCategory: Int] = [:]
        var passthroughCount = 0
        var outletMaterials: [String] = []
        var hubPower = 0.0

        let sim = FlowSimulator.simulate(layout: layout) { recipes(for: $0, in: machineRecipes) }

        for placed in layout.buildings where placed.isActive {
            guard let def = BuildingDefinition.find(placed.definitionID) else { continue }
            // 没通电的建筑不运行，不算耗电；热能池的发电量看燃料，由模拟器给出
            if !sim.unpoweredIDs.contains(placed.id) { totalPowerConsumed += def.powerUsage }
            if def.id != "power_station_1" { hubPower += def.powerGenerate }
            categoryBreakdown[def.category, default: 0] += 1

            if def.id == BuildingDefinition.warehouseOutletID {
                outletMaterials.append(placed.outletMaterialID.flatMap(ItemCatalog.name(for:)) ?? "未设置")
            }
            if def.category == .logistics { passthroughCount += 1 }
        }

        totalPowerGenerated = hubPower + sim.generators.map(\.power).reduce(0, +)

        var outputRates: [String: (rate: Double, buildings: [String: Int])] = [:]
        for machine in sim.machines where !machine.isWarehouseOutlet {
            for (item, perSecond) in machine.outputs where perSecond > 0 {
                var entry = outputRates[item] ?? (rate: 0, buildings: [:])
                entry.rate += perSecond * 60
                entry.buildings[machine.name, default: 0] += 1
                outputRates[item] = entry
            }
        }
        let lines = outputRates.map { key, value in
            ProductionLine(output: key, ratePerMin: value.rate,
                           buildingNames: value.buildings.sorted { $0.key < $1.key }.map { "\($0.key) ×\($0.value)" })
        }.sorted { $0.ratePerMin > $1.ratePerMin }

        var inputRates: [String: (rate: Double, buildings: [String: Int])] = [:]
        func addConsumption(_ item: String, _ perSecond: Double, by name: String) {
            guard perSecond > 1e-9 else { return }
            var entry = inputRates[item] ?? (rate: 0, buildings: [:])
            entry.rate += perSecond * 60
            entry.buildings[name, default: 0] += 1
            inputRates[item] = entry
        }
        for machine in sim.machines {
            for (item, perSecond) in machine.inputs { addConsumption(item, perSecond, by: machine.name) }
        }
        for sink in sim.sinks where !sink.isStorageInlet {
            for (item, perSecond) in sink.consumed { addConsumption(item, perSecond, by: sink.name) }
        }
        for generator in sim.generators {
            guard let name = generator.fuel, let fuel = FuelCatalog.byName[name] else { continue }
            addConsumption(name, generator.fuelRatio / fuel.secondsPerItem, by: generator.name)
        }
        let consumption = inputRates.map { key, value in
            ProductionLine(output: key, ratePerMin: value.rate,
                           buildingNames: value.buildings.sorted { $0.key < $1.key }.map { "\($0.key) ×\($0.value)" })
        }.sorted { $0.ratePerMin > $1.ratePerMin }

        let worst = sim.machines
            .filter { $0.status == .starved || $0.status == .blocked || $0.status == .inactive }
            .min { $0.throttle < $1.throttle }
        var bottleneck: String? = nil
        if let worst {
            let detail = worst.detail.map { "：" + $0 } ?? ""
            bottleneck = "\(worst.name)（\(worst.status.label)\(detail)）"
        }

        return ProductionStats(
            totalPower: totalPowerConsumed - totalPowerGenerated,
            totalPowerConsumed: totalPowerConsumed,
            totalPowerGenerated: totalPowerGenerated,
            hubPower: hubPower,
            generators: sim.generators,
            unpoweredIDs: sim.unpoweredIDs,
            beltFlows: sim.beltFlows,
            buildingCount: layout.buildings.count,
            categoryBreakdown: categoryBreakdown,
            bottleneck: bottleneck,
            productionLines: lines,
            consumptionLines: consumption,
            passthroughCount: passthroughCount,
            outletMaterials: outletMaterials,
            machineStates: sim.machines,
            sinkStates: sim.sinks,
            flowConverged: sim.converged,
            mapConflicts: conflicts
        )
    }

    // MARK: - 地图冲突
    /// 每次重算统计都重新检查：建筑在这张图上不能造、配方模式在这张图上不能用、
    /// 仓库取货口/存货口没贴好（贴的源桩/基段被删了也算）、基段没连着源桩。返回 建筑 ID → 原因
    static func mapConflicts(in layout: FactoryLayout, machineRecipes: [String: [Recipe]]) -> [UUID: String] {
        let rules = layout.mapType.rules
        var conflicts: [UUID: String] = [:]
        for placed in layout.buildings {
            guard let def = BuildingDefinition.find(placed.definitionID) else { continue }
            if !rules.allows(def) {
                let maps = MapRules.maps(allowing: def).map(\.displayName).joined(separator: "、")
                conflicts[placed.id] = "\(layout.mapType.displayName)不能造（仅\(maps)）"
                continue
            }
            let recipeIDs = placed.selectedRecipeIDs.union(placed.selectedRecipeID.map { [$0] } ?? [])
            let blocked = recipes(for: def, in: machineRecipes)
                .filter { recipeIDs.contains($0.id) }
                .compactMap { rules.blockedMode(of: $0, on: def) }
            if let mode = blocked.first {
                conflicts[placed.id] = "\(layout.mapType.displayName)不能用\(mode.name)配方"
                continue
            }
            if BuildingDefinition.warehousePortIDs.contains(def.id) || def.id == BuildingDefinition.warehouseBaseSegmentID {
                let others = layout.buildings.filter { $0.id != placed.id }
                if !canPlace(definition: def, at: placed.origin, rotation: placed.rotation,
                             existing: others, mapType: layout.mapType) {
                    conflicts[placed.id] = dockHint(for: def, rules: rules)
                }
            }
        }
        return conflicts
    }

    private static func dockHint(for def: BuildingDefinition, rules: MapRules) -> String {
        if def.id == BuildingDefinition.warehouseBaseSegmentID { return "没连着仓库存取线源桩" }
        switch rules.warehouseLine {
        case .perimeter(let edges):
            let names: [BuildingRotation: String] = [.up: "上边", .right: "右边", .down: "下边", .left: "左边"]
            let list = BuildingRotation.allCases.filter(edges.contains).compactMap { names[$0] }.joined(separator: "或")
            return "要贴着地图\(list)放，口朝里"
        case .busDock:   return "要贴着仓库存取线源桩或基段放"
        }
    }
}
