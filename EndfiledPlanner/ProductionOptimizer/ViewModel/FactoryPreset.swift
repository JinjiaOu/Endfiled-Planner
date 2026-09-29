//
//  FactoryPreset.swift
//  EndfiledPlanner
//
//  Created by Jinjia Ou on 9/20/26.
//

import Foundation

/// 测试用预设产线：仅用于手动验证流量模拟等功能，会整体替换当前布局（不自动保存）
extension FactoryViewModel {

    /// 四号谷地预设：
    /// - 传送带线：取货口(源矿) → 分流器(只接 2 路) → 两台精炼炉(源矿→晶体外壳) → 汇流器 → 存货口
    /// - 管道线：两台水泵(污水) → 管道汇流器 → 废水处理机（水泵产出 2/s 会顶满废水处理机的 0.5/s，用来测背压）
    func loadTestPreset() {
        var buildings: [PlacedBuilding] = []
        var belts: [Belt] = []

        func pt(_ col: Int, _ row: Int) -> GridPoint { GridPoint(col: col, row: row) }

        func place(_ id: String, _ col: Int, _ row: Int, _ rotation: BuildingRotation,
                   recipe: (machine: String, inputs: [String], output: String)? = nil,
                   material: String? = nil) {
            guard let def = BuildingDefinition.find(id) else {
                print("预设产线：找不到建筑 \(id)")
                return
            }
            guard FactoryGridModel.canPlace(definition: def, at: pt(col, row), rotation: rotation,
                                            existing: buildings, mapType: .valley4) else {
                print("预设产线：\(def.name) 放在 (\(col),\(row)) 不合法")
                return
            }
            var placed = PlacedBuilding(definitionID: id, origin: pt(col, row), rotation: rotation)
            if let recipe {
                placed.selectedRecipeIndex = machineRecipes[recipe.machine]?.firstIndex {
                    $0.inputs.map { $0.name } == recipe.inputs && $0.outputs.map { $0.name } == [recipe.output]
                }
            }
            placed.outletMaterial = material
            buildings.append(placed)
        }

        /// 沿路点连成一条线：路点之间只能水平或垂直；最后一格朝向由 finalDir 指定（输入口要对准流入方向）
        func belt(_ waypoints: [GridPoint], finalDir: BuildingRotation, type: LineType) {
            var cells: [GridPoint] = []
            for (i, p) in waypoints.enumerated() {
                if i == 0 { cells.append(p); continue }
                var cur = cells[cells.count - 1]
                let stepCol = p.col == cur.col ? 0 : (p.col > cur.col ? 1 : -1)
                let stepRow = p.row == cur.row ? 0 : (p.row > cur.row ? 1 : -1)
                while cur != p {
                    cur = pt(cur.col + stepCol, cur.row + stepRow)
                    cells.append(cur)
                }
            }
            var segments: [BeltSegment] = []
            for (i, cell) in cells.enumerated() {
                let dir: GridPoint
                if i < cells.count - 1 {
                    let next = cells[i + 1]
                    dir = pt(next.col - cell.col, next.row - cell.row)
                } else {
                    dir = finalDir.outputOffset
                }
                let axis: BeltAxis = dir.col == 0 ? .vertical : .horizontal
                segments.append(BeltSegment(cell: cell, axis: axis, fromDir: dir, toDir: dir, lineType: type))
            }
            belts.append(Belt(segments: segments))
        }

        // MARK: 传送带线（顶边取货口 → 左边存货口）
        place("unloader_1", 2, 0, .down, material: "源矿")
        place("log_splitter", 3, 4, .down)
        place("furnance_1", 0, 8, .down, recipe: ("精炼炉", ["源矿"], "晶体外壳"))
        place("furnance_1", 5, 8, .down, recipe: ("精炼炉", ["源矿"], "晶体外壳"))
        place("log_converger", 4, 13, .down)
        place("loader_1", 0, 15, .right)

        belt([pt(3, 1), pt(3, 3)], finalDir: .down, type: .belt)                       // 取货口 → 分流器
        belt([pt(2, 4), pt(2, 7)], finalDir: .down, type: .belt)                       // 分流器左出 → 精炼炉 A
        belt([pt(4, 4), pt(5, 4), pt(5, 7)], finalDir: .down, type: .belt)             // 分流器右出 → 精炼炉 B
        belt([pt(2, 11), pt(2, 13), pt(3, 13)], finalDir: .right, type: .belt)         // 精炼炉 A → 汇流器
        belt([pt(5, 11), pt(5, 13)], finalDir: .left, type: .belt)                     // 精炼炉 B → 汇流器
        belt([pt(4, 14), pt(4, 16), pt(1, 16)], finalDir: .left, type: .belt)          // 汇流器 → 存货口

        // MARK: 管道线（两台二型耐酸水泵 → 管道汇流器 → 废水处理机）
        // 水泵(pump_1)实际只能抽清水，污水只有二型耐酸水泵(pump_2)能选，这里改成 pump_2
        place("pump_2", 12, 5, .up, recipe: ("二型耐酸水泵", [], "污水"))
        place("pump_2", 12, 11, .up, recipe: ("二型耐酸水泵", [], "污水"))
        place("log_pipe_converger", 17, 9, .right)
        place("liquid_cleaner_1", 19, 8, .up)

        belt([pt(15, 6), pt(17, 6), pt(17, 8)], finalDir: .down, type: .pipe)          // 水泵 A → 汇流器上口
        belt([pt(15, 12), pt(17, 12), pt(17, 10)], finalDir: .up, type: .pipe)         // 水泵 B → 汇流器下口
        belt([pt(18, 9)], finalDir: .right, type: .pipe)                               // 汇流器 → 废水处理机

        layout = FactoryLayout(buildings: buildings, beltNetwork: BeltNetwork(belts: belts),
                               savedAt: .now, mapType: .valley4)
        FactoryGridModel.ensureProtocolCore(in: &layout)
        editMode = .select
        selectedBuildingID = nil
        beltStart = nil
        beltPreviewSegments = []
        pendingEraseBeltIDs = []
        refreshStats()
    }

    // MARK: - 武陵：重息壤自我供给对比（单上游 vs 最少上游喂满下游）

    /// 查某个建筑（假设按给定坐标/朝向摆放）某个口的外部衔接格 + 流入/流出该点时线路该朝哪个方向摆最后一段。
    /// 直接用建筑自己的 resolvedPosition 算，不手推坐标，减少出错概率。
    /// - Parameters:
    ///   - kind/direction: 口的类型和方向
    ///   - edge: 可选，进一步按未旋转前所在边过滤（比如转化机的激活口是 .down 边）
    ///   - nth: 同类型同方向的口有多个时，第几个（0 开始）
    private func portExternal(_ id: String, at origin: GridPoint, rotation: BuildingRotation = .up,
                              kind: PortKind, direction: PortIODirection, edge: BuildingRotation? = nil,
                              nth: Int = 0) -> (cell: GridPoint, finalDir: BuildingRotation)? {
        guard let def = BuildingDefinition.find(id) else { return nil }
        let dummy = PlacedBuilding(definitionID: id, origin: origin, rotation: rotation)
        let matches = def.ports.filter { $0.kind == kind && $0.ioDirection == direction && (edge == nil || $0.edge == edge) }
        guard matches.indices.contains(nth) else { return nil }
        let (cell, facing) = matches[nth].resolvedPosition(placed: dummy, definition: def)
        let external = GridPoint(col: cell.col + facing.outputOffset.col, row: cell.row + facing.outputOffset.row)
        // 输出口：流出方向就是 facing；输入口：实际流入方向是 facing 的反方向
        let finalDir = direction == .output ? facing : BuildingRotation(rawValue: (facing.rawValue + 2) % 4) ?? facing
        return (external, finalDir)
    }

    /// 武陵地图，目标产物重息壤（天有洪炉：息壤×10+壤晶废液×5→重息壤×1，满载需要息壤60/min+壤晶废液30/min）。
    /// 两个场景对比"上游机组数量"对下游负载的影响，壤晶废液链两边完全独立、各自饱和，唯一变量是息壤链的机组数：
    /// - 场景 A（单上游）：1 组"3 气泵+1 固气转化机"，只给 30/min 息壤 → 天有洪炉 A 缺一半，预期 50%，产 3/min 重息壤
    /// - 场景 B（最少上游喂满）：2 组同样组合，合计 60/min 息壤正好等于需求 → 天有洪炉 B 预期 100%，产 6/min 重息壤
    /// 息壤链每组：2 台气泵直连转化机的两个配方口（各 20/min，合计 40/min ≥ 配方需要的 30/min）+ 1 台气泵直连激活口
    /// （20/min ≥ 激活最低需要的 6/min），转化机满载输出 30/min 息壤。
    /// 壤晶废液链每套：2 台二型耐酸水泵（选液化息壤/污水配方，各 60/min，远超反应池需要的量）→ 1 台反应池
    /// （液化息壤+污水→壤晶废液+惰性壤晶废液，满载 30/min 壤晶废液正好等于炉子需求）→ 惰性壤晶废液副产物接废水处理机吃掉。
    func loadWulingSelfSupplyPreset() {
        var buildings: [PlacedBuilding] = []
        var belts: [Belt] = []

        func pt(_ col: Int, _ row: Int) -> GridPoint { GridPoint(col: col, row: row) }

        func place(_ id: String, _ col: Int, _ row: Int, _ rotation: BuildingRotation,
                   recipe: (machine: String, inputs: [String], output: String)? = nil,
                   recipeIndices: Set<Int>? = nil) {
            guard let def = BuildingDefinition.find(id) else {
                print("武陵预设：找不到建筑 \(id)")
                return
            }
            guard FactoryGridModel.canPlace(definition: def, at: pt(col, row), rotation: rotation,
                                            existing: buildings, mapType: .wuling) else {
                print("武陵预设：\(def.name) 放在 (\(col),\(row)) 不合法")
                return
            }
            var placed = PlacedBuilding(definitionID: id, origin: pt(col, row), rotation: rotation)
            if let recipe {
                placed.selectedRecipeIndex = machineRecipes[recipe.machine]?.firstIndex {
                    $0.inputs.map { $0.name } == recipe.inputs && $0.outputs.map { $0.name } == [recipe.output]
                }
            }
            if let recipeIndices { placed.selectedRecipeIndices = recipeIndices }
            buildings.append(placed)
        }

        func belt(_ waypoints: [GridPoint], finalDir: BuildingRotation, type: LineType) {
            var cells: [GridPoint] = []
            for (i, p) in waypoints.enumerated() {
                if i == 0 { cells.append(p); continue }
                var cur = cells[cells.count - 1]
                let stepCol = p.col == cur.col ? 0 : (p.col > cur.col ? 1 : -1)
                let stepRow = p.row == cur.row ? 0 : (p.row > cur.row ? 1 : -1)
                while cur != p {
                    cur = pt(cur.col + stepCol, cur.row + stepRow)
                    cells.append(cur)
                }
            }
            var segments: [BeltSegment] = []
            for (i, cell) in cells.enumerated() {
                let dir: GridPoint
                if i < cells.count - 1 {
                    let next = cells[i + 1]
                    dir = pt(next.col - cell.col, next.row - cell.row)
                } else {
                    dir = finalDir.outputOffset
                }
                let axis: BeltAxis = dir.col == 0 ? .vertical : .horizontal
                segments.append(BeltSegment(cell: cell, axis: axis, fromDir: dir, toDir: dir, lineType: type))
            }
            belts.append(Belt(segments: segments))
        }

        /// 从某个"输出口外部格"直连到某个"输入口外部格"，两点之间自动补一个直角拐点
        func connect(from: (cell: GridPoint, finalDir: BuildingRotation)?, to: (cell: GridPoint, finalDir: BuildingRotation)?, type: LineType) {
            guard let from, let to else { print("武陵预设：口位置没算出来，连线跳过"); return }
            // 两个口的外部衔接格刚好是同一格时也要落一段"零长度"的带/管来注册连接，不能直接跳过不摆
            if from.cell.col == to.cell.col || from.cell.row == to.cell.row {
                belt([from.cell, to.cell], finalDir: to.finalDir, type: type)
            } else {
                belt([from.cell, pt(to.cell.col, from.cell.row), to.cell], finalDir: to.finalDir, type: type)
            }
        }

        /// 息壤链一组：2 台气泵接转化机配方口 + 1 台气泵接激活口 → 转化机(息壤气→息壤)，返回息壤输出口的外部格信息
        func buildXiraniteGasUnit(originCol: Int, originRow: Int) -> (cell: GridPoint, finalDir: BuildingRotation)? {
            let tCol = originCol + 4, tRow = originRow
            place("transmuter_2", tCol, tRow, .up)
            guard let recipeIdx = machineRecipes["固气转化机"]?.firstIndex(where: {
                $0.inputs.map { $0.name } == ["息壤气"] && $0.outputs.map { $0.name } == ["息壤"]
            }), let idx = buildings.indices.last else { return nil }
            buildings[idx].selectedRecipeIndex = recipeIdx

            guard let recipeA = portExternal("transmuter_2", at: pt(tCol, tRow), kind: .pipe, direction: .input, edge: .left, nth: 0),
                  let recipeB = portExternal("transmuter_2", at: pt(tCol, tRow), kind: .pipe, direction: .input, edge: .left, nth: 1),
                  let activator = portExternal("transmuter_2", at: pt(tCol, tRow), kind: .pipe, direction: .input, edge: .down),
                  let output = portExternal("transmuter_2", at: pt(tCol, tRow), kind: .item, direction: .output, nth: 0)
            else { print("武陵预设：转化机口位置算不出来"); return nil }

            // 两台气泵各接一个配方口（各 20/min，合计 40/min ≥ 30/min 需求）
            place("gas_pump_1", originCol, originRow, .up, recipe: ("气体收集泵", [], "息壤气"))
            if let pumpOut = portExternal("gas_pump_1", at: pt(originCol, originRow), kind: .pipe, direction: .output) {
                connect(from: pumpOut, to: recipeA, type: .pipe)
            }
            place("gas_pump_1", originCol, originRow + 4, .up, recipe: ("气体收集泵", [], "息壤气"))
            if let pumpOut = portExternal("gas_pump_1", at: pt(originCol, originRow + 4), kind: .pipe, direction: .output) {
                connect(from: pumpOut, to: recipeB, type: .pipe)
            }
            // 第三台气泵单独接激活口（20/min ≥ 6/min 最低需求）
            place("gas_pump_1", originCol, originRow + 8, .up, recipe: ("气体收集泵", [], "息壤气"))
            if let pumpOut = portExternal("gas_pump_1", at: pt(originCol, originRow + 8), kind: .pipe, direction: .output) {
                connect(from: pumpOut, to: activator, type: .pipe)
            }
            return output
        }

        /// 壤晶废液链一套：2 台二型耐酸水泵(液化息壤/污水) → 反应池 → 惰性壤晶废液接废水处理机，
        /// 返回壤晶废液输出口的外部格信息
        func buildXiraniteWasteUnit(originCol: Int, originRow: Int) -> (cell: GridPoint, finalDir: BuildingRotation)? {
            let poolCol = originCol + 4, poolRow = originRow
            place("mix_pool_1", poolCol, poolRow, .up)
            guard let idxLiquid = machineRecipes["反应池"]?.firstIndex(where: {
                $0.inputs.map { $0.name } == ["液化息壤", "污水"] && $0.outputs.map { $0.name } == ["壤晶废液", "惰性壤晶废液"]
            }), let idx = buildings.indices.last else { return nil }
            buildings[idx].selectedRecipeIndex = idxLiquid

            guard let inXiranite = portExternal("mix_pool_1", at: pt(poolCol, poolRow), kind: .pipe, direction: .input, nth: 0),
                  let inSewage = portExternal("mix_pool_1", at: pt(poolCol, poolRow), kind: .pipe, direction: .input, nth: 1),
                  let outWaste = portExternal("mix_pool_1", at: pt(poolCol, poolRow), kind: .pipe, direction: .output, nth: 0),
                  let outLowpoly = portExternal("mix_pool_1", at: pt(poolCol, poolRow), kind: .pipe, direction: .output, nth: 1)
            else { print("武陵预设：反应池口位置算不出来"); return nil }

            place("pump_2", originCol, originRow, .up, recipe: ("二型耐酸水泵", [], "液化息壤"))
            if let pumpOut = portExternal("pump_2", at: pt(originCol, originRow), kind: .pipe, direction: .output) {
                connect(from: pumpOut, to: inXiranite, type: .pipe)
            }
            place("pump_2", originCol, originRow + 4, .up, recipe: ("二型耐酸水泵", [], "污水"))
            if let pumpOut = portExternal("pump_2", at: pt(originCol, originRow + 4), kind: .pipe, direction: .output) {
                connect(from: pumpOut, to: inSewage, type: .pipe)
            }

            // 废水处理机放在反应池正下方（不是右边）：壤晶废液主输出口要往右一路通到炉子，
            // 放右边会正好挡在这条路中间
            let cleanerCol = poolCol, cleanerRow = poolRow + 6
            place("liquid_cleaner_1", cleanerCol, cleanerRow, .up)
            if let cleanerIn = portExternal("liquid_cleaner_1", at: pt(cleanerCol, cleanerRow), kind: .pipe, direction: .input) {
                // 手动绕路：先往下清出反应池本体的行范围，再往下清出废水处理机本体的行范围，
                // 再横移到目标列，最后往上顶到入口——避免 connect() 的单拐点直接从反应池/废水处理机中间穿过去
                belt([outLowpoly.cell, pt(outLowpoly.cell.col, cleanerRow + 3), pt(cleanerIn.cell.col, cleanerRow + 3), cleanerIn.cell],
                     finalDir: cleanerIn.finalDir, type: .pipe)
            }
            return outWaste
        }

        /// 一台天有洪炉（不转向，.up），外加它自己专用的一套源桩+存货口（紧贴在源桩上，不用长距离连线到别处的源桩）：
        /// 接息壤输入（可以传 1~2 个来源，对应炉子 5 个物品输入口里的前几个，都从南边进）、
        /// 壤晶废液输入（从西边进），重息壤接存货口（从北边出，源桩+存货口摆在炉子正上方）
        func buildFurnace(col: Int, row: Int, xiraniteOuts: [(cell: GridPoint, finalDir: BuildingRotation)?],
                          wasteOut: (cell: GridPoint, finalDir: BuildingRotation)?) {
            place("xiranite_oven_1", col, row, .up)
            guard let idxHeavy = machineRecipes["天有洪炉"]?.firstIndex(where: {
                $0.inputs.map { $0.name } == ["息壤", "壤晶废液"] && $0.outputs.map { $0.name } == ["重息壤"]
            }), let idx = buildings.indices.last else { return }
            buildings[idx].selectedRecipeIndex = idxHeavy

            for (nth, xiraniteOut) in xiraniteOuts.enumerated() {
                if let xiraniteIn = portExternal("xiranite_oven_1", at: pt(col, row), kind: .item, direction: .input, nth: nth) {
                    connect(from: xiraniteOut, to: xiraniteIn, type: .belt)
                }
            }
            if let wasteIn = portExternal("xiranite_oven_1", at: pt(col, row), kind: .pipe, direction: .input) {
                connect(from: wasteOut, to: wasteIn, type: .pipe)
            }
            guard let heavyOut = portExternal("xiranite_oven_1", at: pt(col, row), kind: .item, direction: .output, nth: 0)
            else { return }

            // 本地专属的源桩+存货口：源桩放在炉子正上方留出一段空档的位置，存货口紧贴源桩南边摆，
            // 摆放朝向按四个方向试哪个能贴上，跟拖拽放置时的自动定向逻辑一样
            let sourceCol = col, sourceRow = row - 9
            place("log_hongs_bus_source", sourceCol, sourceRow, .up)
            let loaderCol = col, loaderRow = sourceRow + 4
            guard let loaderDef = BuildingDefinition.find(BuildingDefinition.warehouseInletID) else { return }
            for candidate in BuildingRotation.allCases {
                guard FactoryGridModel.canPlace(definition: loaderDef, at: pt(loaderCol, loaderRow), rotation: candidate,
                                                existing: buildings, mapType: .wuling) else { continue }
                place(BuildingDefinition.warehouseInletID, loaderCol, loaderRow, candidate)
                if let loaderIn = portExternal(BuildingDefinition.warehouseInletID, at: pt(loaderCol, loaderRow),
                                               rotation: candidate, kind: .item, direction: .input) {
                    connect(from: heavyOut, to: loaderIn, type: .belt)
                }
                break
            }
        }

        // 地图左半（cols0-29）：场景 A（单上游）：1 组息壤链 + 1 套壤晶废液链 → 天有洪炉 A（预期 50%，3/min 重息壤）
        let xiraniteA = buildXiraniteGasUnit(originCol: 20, originRow: 25)
        let wasteA = buildXiraniteWasteUnit(originCol: 10, originRow: 16)
        buildFurnace(col: 25, row: 15, xiraniteOuts: [xiraniteA], wasteOut: wasteA)

        // 地图右半（cols30-59）：场景 B（最少上游喂满下游）：2 组息壤链堆叠（各接炉子一个物品输入口）
        // + 1 套壤晶废液链 → 天有洪炉 B（预期 100%，6/min 重息壤）
        let xiraniteB1 = buildXiraniteGasUnit(originCol: 30, originRow: 25)
        let xiraniteB2 = buildXiraniteGasUnit(originCol: 30, originRow: 36)
        let wasteB = buildXiraniteWasteUnit(originCol: 30, originRow: 15)
        buildFurnace(col: 50, row: 15, xiraniteOuts: [xiraniteB1, xiraniteB2], wasteOut: wasteB)

        layout = FactoryLayout(buildings: buildings, beltNetwork: BeltNetwork(belts: belts),
                               savedAt: .now, mapType: .wuling)
        FactoryGridModel.ensureProtocolCore(in: &layout)
        editMode = .select
        selectedBuildingID = nil
        beltStart = nil
        beltPreviewSegments = []
        pendingEraseBeltIDs = []
        refreshStats()
    }
}
