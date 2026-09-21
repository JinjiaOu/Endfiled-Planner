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

        // MARK: 管道线（两台水泵 → 管道汇流器 → 废水处理机）
        place("pump_1", 12, 5, .up, recipe: ("水泵", [], "污水"))
        place("pump_1", 12, 11, .up, recipe: ("水泵", [], "污水"))
        place("log_pipe_converger", 17, 9, .right)
        place("liquid_cleaner_1", 19, 8, .up)

        belt([pt(15, 6), pt(17, 6), pt(17, 8)], finalDir: .down, type: .pipe)          // 水泵 A → 汇流器上口
        belt([pt(15, 12), pt(17, 12), pt(17, 10)], finalDir: .up, type: .pipe)         // 水泵 B → 汇流器下口
        belt([pt(18, 9)], finalDir: .right, type: .pipe)                               // 汇流器 → 废水处理机

        layout = FactoryLayout(buildings: buildings, beltNetwork: BeltNetwork(belts: belts),
                               savedAt: .now, mapType: .valley4)
        editMode = .select
        selectedBuildingID = nil
        beltStart = nil
        beltPreviewSegments = []
        pendingEraseBeltIDs = []
        refreshStats()
    }
}
