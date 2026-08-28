//
//  FactoryGridModel.swift
//  EndfiledPlanner
//
//  Created by Jinjia Ou on 4/3/26.
//

import Foundation

// MARK: - 布局快照（用于序列化）
struct FactoryLayout: Codable {
    var buildings: [PlacedBuilding]
    var beltNetwork: BeltNetwork
    var savedAt: Date
    var mapType: MapType

    static let empty = FactoryLayout(buildings: [], beltNetwork: BeltNetwork(), savedAt: .now, mapType: .valley4)

    init(buildings: [PlacedBuilding], beltNetwork: BeltNetwork, savedAt: Date, mapType: MapType) {
        self.buildings = buildings
        self.beltNetwork = beltNetwork
        self.savedAt = savedAt
        self.mapType = mapType
    }

    private enum CodingKeys: String, CodingKey {
        case buildings, beltNetwork, savedAt, mapType
    }

    // 旧存档没有 mapType 字段，缺省当四号谷地处理，不然老存档会直接读取失败被清空
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        buildings = try c.decode([PlacedBuilding].self, forKey: .buildings)
        beltNetwork = try c.decode(BeltNetwork.self, forKey: .beltNetwork)
        savedAt = try c.decode(Date.self, forKey: .savedAt)
        mapType = try c.decodeIfPresent(MapType.self, forKey: .mapType) ?? .valley4
    }
}

// MARK: - 网格模型
class FactoryGridModel {

    static let gridCols = 60
    static let gridRows = 48

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

    // MARK: - 碰撞检测
    /// 检查新建筑是否与已有建筑重叠，并且符合当前地图的专属放置规则
    static func canPlace(
        definition: BuildingDefinition,
        at origin: GridPoint,
        rotation: BuildingRotation,
        existing: [PlacedBuilding],
        mapType: MapType
    ) -> Bool {
        // 这个建筑本来就不允许出现在当前地图（比如取线终端在四号谷地）
        guard definition.isAvailable(on: mapType) else { return false }

        let dummy = PlacedBuilding(definitionID: definition.id, origin: origin, rotation: rotation)
        let newCellsArr = dummy.occupiedCells(definition: definition)
        let newCells = Set(newCellsArr.map { "\($0.col),\($0.row)" })

        // 边界检查
        let size = dummy.effectiveSize(definition: definition)
        if origin.col < 0 || origin.row < 0 { return false }
        if origin.col + size.width > gridCols { return false }
        if origin.row + size.height > gridRows { return false }

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
            switch mapType {
            case .valley4:
                guard isFlushOnValley4Edge(placed: dummy, definition: definition) else { return false }
            case .wuling:
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

    /// 四号谷地：只允许上边和左边这两条边（绕基地半圈），不是四条边都能放
    static let valley4PerimeterEdges: Set<BuildingRotation> = [.up, .left]

    /// 仓库取货口/存货口是长条形（比如 3x1），必须长边整条贴死在允许的那条边上。
    /// 关键点：口要朝地图内部开（贴上边→朝下，贴左边→朝右），不是朝边界外——
    /// 朝外的话外面连接格会落在网格范围之外，传送带根本没地方接。
    static func isFlushOnValley4Edge(placed: PlacedBuilding, definition: BuildingDefinition) -> Bool {
        guard let port = definition.ports.first else { return false }
        let (portCell, facing) = port.resolvedPosition(placed: placed, definition: definition)
        if valley4PerimeterEdges.contains(.up) && facing == .down && portCell.row == 0 { return true }
        if valley4PerimeterEdges.contains(.left) && facing == .right && portCell.col == 0 { return true }
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
        let totalPower: Double          // 总功率消耗 (MW)
        let buildingCount: Int
        let categoryBreakdown: [BuildingCategory: Int]
        let bottleneck: String?         // 瓶颈建筑名称
        let productionLines: [ProductionLine]
        let passthroughCount: Int       // 分流器/汇流器/物流桥这类直通节点数量（不产不耗，不算进产线）
        let outletMaterials: [String]   // 每个取线出口当前设置的材料（未设置显示"未设置"），仓库取线没有速率概念，单独列出来
    }

    struct ProductionLine {
        let output: String
        let ratePerMin: Double
        let buildingNames: [String]
    }

    /// - Parameter machineRecipes: 按机器名分组去重的配方表（RecipeViewModel.recipesByMachine()），
    ///   selectedRecipeIndex 就是这个表里对应机器那份列表的下标
    static func analyze(layout: FactoryLayout, machineRecipes: [String: [Recipe]]) -> ProductionStats {
        var totalPower = 0.0
        var categoryBreakdown: [BuildingCategory: Int] = [:]
        var passthroughCount = 0
        var outletMaterials: [String] = []

        // V1：按"建筑类型 + 已选配方"分组，算每组的理论产出速率。
        // 不做传送带连通性分析，也不做瓶颈检测（瓶颈需要匹配下游消耗速率，工作量较大，先留空）。
        struct GroupKey: Hashable { let defID: String; let recipeIndex: Int }
        var groups: [GroupKey: Int] = [:]   // 每组建筑数量

        for placed in layout.buildings where placed.isActive {
            guard let def = BuildingDefinition.find(placed.definitionID) else { continue }
            totalPower += def.powerUsage
            categoryBreakdown[def.category, default: 0] += 1

            // 仓库取货口没有配方，产出的是用户自己设置的材料，单独列出来
            if def.id == BuildingDefinition.warehouseOutletID {
                outletMaterials.append(placed.outletMaterial ?? "未设置")
                continue
            }

            // 分流器/汇流器/物流桥/取线终端这类物流节点不在 recipes.txt 里，没有配方可选，
            // 单独计数标出来，别让它们看起来像是"被漏统计"了
            if def.category == .logistics {
                passthroughCount += 1
                continue
            }

            guard let idx = placed.selectedRecipeIndex else { continue }
            groups[GroupKey(defID: placed.definitionID, recipeIndex: idx), default: 0] += 1
        }

        var outputRates: [String: (rate: Double, buildings: [String])] = [:]
        for (key, count) in groups {
            guard let def = BuildingDefinition.find(key.defID),
                  let recipeList = machineRecipes[def.name],
                  key.recipeIndex >= 0, key.recipeIndex < recipeList.count
            else { continue }
            let recipe = recipeList[key.recipeIndex]
            // 挖矿类设备的耗时不计入生产链瓶颈判断，但产出速率本身仍然按配方算
            for output in recipe.outputs {
                let rate = (Double(output.count) / Double(recipe.time)) * 60 * Double(count)
                var entry = outputRates[output.name] ?? (rate: 0, buildings: [])
                entry.rate += rate
                entry.buildings.append("\(def.name) ×\(count)")
                outputRates[output.name] = entry
            }
        }

        let lines = outputRates.map { key, value in
            ProductionLine(output: key, ratePerMin: value.rate, buildingNames: value.buildings)
        }.sorted { $0.ratePerMin > $1.ratePerMin }

        return ProductionStats(
            totalPower: totalPower,
            buildingCount: layout.buildings.count,
            categoryBreakdown: categoryBreakdown,
            bottleneck: nil,
            productionLines: lines,
            passthroughCount: passthroughCount,
            outletMaterials: outletMaterials
        )
    }
}
