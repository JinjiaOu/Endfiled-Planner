//
//  FactoryViewModel+Placement.swift
//  EndfiledPlanner
//

import Foundation

// MARK: - 把"我的布局"放到画布上（M4 第 3 步）
// 列表里点一个 → 整组虚影出现在画面中央，跟手拖动、可整体旋转 90°，点"确认"才写入（一步撤销），可取消。
// 压到已有建筑/出界不能确认。跨地图可以放：放之前提醒，放下后冲突建筑由地图冲突检查标红、不参与模拟

/// 正在摆的布局：origin 是虚影外框左上角在画布上的格子，quarterTurns 是顺时针转了几个 90°
struct PendingPlacement {
    let saved: SavedLayout
    var origin: GridPoint
    var quarterTurns: Int = 0

    /// 转完之后的外框大小
    var size: GridSize {
        quarterTurns % 2 == 0 ? GridSize(width: saved.width, height: saved.height)
                              : GridSize(width: saved.height, height: saved.width)
    }

    /// 转完、平移到 origin 之后的建筑（ID 还是存档里的，确认写入时才换新）
    var buildings: [PlacedBuilding] {
        saved.buildings.compactMap { placed in
            guard let def = BuildingDefinition.find(placed.definitionID) else { return nil }
            var copy = placed
            var w = saved.width, h = saved.height
            for _ in 0..<(quarterTurns % 4) {
                // 整组顺时针转 90°：外框 w×h 变成 h×w，建筑占的矩形 (c0, r0, 宽, 高) 落到 (h - r0 - 高, c0)，自身朝向也转一下
                let s = copy.effectiveSize(definition: def)
                copy.origin = GridPoint(col: h - copy.origin.row - s.height, row: copy.origin.col)
                copy.rotation = copy.rotation.next
                swap(&w, &h)
            }
            copy.origin = copy.origin + origin
            return copy
        }
    }

    /// 转完、平移到 origin 之后的线
    var belts: [Belt] {
        saved.belts.map { belt in
            var copy = belt
            var w = saved.width, h = saved.height
            for _ in 0..<(quarterTurns % 4) {
                for i in copy.segments.indices {
                    var seg = copy.segments[i]
                    seg.cell = GridPoint(col: h - 1 - seg.cell.row, row: seg.cell.col)
                    // 方向顺时针转：右→下→左→上（屏幕坐标 y 向下）
                    seg.fromDir = GridPoint(col: -seg.fromDir.row, row: seg.fromDir.col)
                    seg.toDir = GridPoint(col: -seg.toDir.row, row: seg.toDir.col)
                    seg.axis = seg.axis == .horizontal ? .vertical : .horizontal
                    copy.segments[i] = seg
                }
                swap(&w, &h)
            }
            for i in copy.segments.indices { copy.segments[i].cell = copy.segments[i].cell + origin }
            return copy
        }
    }
}

extension FactoryViewModel {

    /// 跨地图放置前的提醒：这份布局放到当前地图后哪些建筑会冲突（名字 → 个数 + 原因）；同地图返回空
    func placementWarnings(for saved: SavedLayout) -> [String] {
        let map = layout.mapType
        guard saved.mapType != map else { return [] }
        let rules = map.rules
        var counts: [String: Int] = [:]
        for placed in saved.buildings {
            guard let def = BuildingDefinition.find(placed.definitionID) else { continue }
            let reason: String?
            if !rules.allows(def) {
                reason = "\(def.name)（\(map.displayName)不能造）"
            } else if let mode = recipesOf(placed, def: def).compactMap({ rules.blockedMode(of: $0, on: def) }).first {
                reason = "\(def.name)（\(mode.name)配方\(map.displayName)不能用）"
            } else if BuildingDefinition.warehousePortIDs.contains(def.id) {
                reason = "\(def.name)（两张地图接仓库的方式不同，要重新贴好）"
            } else {
                reason = nil
            }
            if let reason { counts[reason, default: 0] += 1 }
        }
        var lines = counts.sorted { $0.key < $1.key }.map { "\($0.key) ×\($0.value)" }
        let pipeCount = saved.belts.filter { $0.lineType == .pipe }.count
        if !rules.allowsPipes && pipeCount > 0 {
            lines.append("管道 ×\(pipeCount)（\(map.displayName)不能用管道，不参与计算）")
        }
        return lines
    }

    private func recipesOf(_ placed: PlacedBuilding, def: BuildingDefinition) -> [Recipe] {
        let ids = placed.selectedRecipeIDs.union(placed.selectedRecipeID.map { [$0] } ?? [])
        return availableRecipes(for: def).filter { ids.contains($0.id) }
    }

    /// 开始摆：虚影放在 center（画面中央那一格）附近，外框不出界
    func startPlacement(_ saved: SavedLayout, around center: GridPoint) {
        editMode = .select
        clearSelection()
        var placement = PendingPlacement(saved: saved, origin: .init(col: 0, row: 0))
        placement.origin = clampedOrigin(GridPoint(col: center.col - saved.width / 2, row: center.row - saved.height / 2),
                                         size: placement.size)
        pendingPlacement = placement
    }

    func movePlacement(to origin: GridPoint) {
        guard var placement = pendingPlacement else { return }
        placement.origin = clampedOrigin(origin, size: placement.size)
        pendingPlacement = placement
    }

    /// 整体顺时针转 90°，绕外框中心转，转完尽量还在原地
    func rotatePlacement() {
        guard var placement = pendingPlacement else { return }
        let old = placement.size
        placement.quarterTurns = (placement.quarterTurns + 1) % 4
        let new = placement.size
        let shifted = GridPoint(col: placement.origin.col + (old.width - new.width) / 2,
                                row: placement.origin.row + (old.height - new.height) / 2)
        placement.origin = clampedOrigin(shifted, size: new)
        pendingPlacement = placement
    }

    func cancelPlacement() {
        pendingPlacement = nil
    }

    private func clampedOrigin(_ origin: GridPoint, size: GridSize) -> GridPoint {
        let rules = layout.mapType.rules
        return GridPoint(col: min(max(origin.col, 0), max(0, rules.gridCols - size.width)),
                         row: min(max(origin.row, 0), max(0, rules.gridRows - size.height)))
    }

    /// 能不能确认：建筑不能出界、不能压到已有建筑；线不能出界、不能穿过已有建筑（物流桥除外）。
    /// 地图规则不挡放置，放下后由地图冲突检查标红
    var placementBlockedReason: String? {
        guard let placement = pendingPlacement else { return nil }
        let rules = layout.mapType.rules
        func outOfBounds(_ cell: GridPoint) -> Bool {
            cell.col < 0 || cell.row < 0 || cell.col >= rules.gridCols || cell.row >= rules.gridRows
        }
        var occupied = Set<GridPoint>()
        var blocking = Set<GridPoint>()
        for placed in layout.buildings {
            guard let def = BuildingDefinition.find(placed.definitionID) else { continue }
            let cells = placed.occupiedCells(definition: def)
            occupied.formUnion(cells)
            if !FactoryViewModel.bridgeBuildingIDs.contains(def.id) { blocking.formUnion(cells) }
        }
        for placed in placement.buildings {
            guard let def = BuildingDefinition.find(placed.definitionID) else { continue }
            for cell in placed.occupiedCells(definition: def) {
                if outOfBounds(cell) { return "超出画布了" }
                if occupied.contains(cell) { return "压到已有的建筑了，挪开再确认" }
            }
        }
        for belt in placement.belts {
            for seg in belt.segments {
                if outOfBounds(seg.cell) { return "超出画布了" }
                if blocking.contains(seg.cell) { return "线穿过了已有的建筑，挪开再确认" }
            }
        }
        return nil
    }

    /// 写入画布（一步撤销）：建筑和线都换新 ID；配方、取货材料在当前数据里找不到的清成"未设置"
    func confirmPlacement() {
        guard let placement = pendingPlacement, placementBlockedReason == nil else { return }
        beginUndoGroup()
        defer { endUndoGroup() }
        for var placed in placement.buildings {
            guard let def = BuildingDefinition.find(placed.definitionID) else { continue }
            placed.id = UUID()
            let known = Set(availableRecipes(for: def).map(\.id))
            if let id = placed.selectedRecipeID, !known.contains(id) { placed.selectedRecipeID = nil }
            placed.selectedRecipeIDs = placed.selectedRecipeIDs.filter(known.contains)
            if let item = placed.outletMaterialID, ItemCatalog.name(for: item) == nil { placed.outletMaterialID = nil }
            if let item = placed.filterItemID, ItemCatalog.name(for: item) == nil { placed.filterItemID = nil }
            layout.buildings.append(placed)
        }
        for belt in placement.belts where !belt.segments.isEmpty {
            // 段也换新 ID，同一份布局放两次不会撞
            let segments = belt.segments.map {
                BeltSegment(cell: $0.cell, axis: $0.axis, fromDir: $0.fromDir, toDir: $0.toDir, lineType: $0.lineType)
            }
            layout.beltNetwork.belts.append(Belt(segments: segments))
        }
        // 跟已有的同类线十字交叉的地方照常自动放桥
        for belt in placement.belts {
            for seg in belt.segments { autoPlaceBridgeIfCrossing(at: seg.cell, lineType: seg.lineType) }
        }
        pendingPlacement = nil
        refreshStats()
    }
}
