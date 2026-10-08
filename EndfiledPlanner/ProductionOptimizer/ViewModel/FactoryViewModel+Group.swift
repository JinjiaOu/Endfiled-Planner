//
//  FactoryViewModel+Group.swift
//  EndfiledPlanner
//

import Foundation

// MARK: - 框选 + 整组操作（M4 第 1 步）
// 框选模式下：拖框把整个落在框里的建筑和整条落在框里的线加进选中，点单个建筑/线加入/移出；协议核心不参与。
// 按住任一选中建筑拖动整组；跟着整条平移的线见 beltsMovingWithGroup，一头接组外的线按 M3 的改接逻辑重走。
// 整组移动/删除都算一步撤销
extension FactoryViewModel {

    var groupBuildings: [PlacedBuilding] {
        layout.buildings.filter { groupSelection.contains($0.id) }
    }

    var hasGroupSelection: Bool { !groupSelection.isEmpty || !groupBeltSelection.isEmpty }

    /// 框选：a、b 是框的两个对角格（含）。建筑占的格子全在框里才算，线要整条都在框里才算，加进当前选中
    func boxSelect(from a: GridPoint, to b: GridPoint) {
        let cols = min(a.col, b.col)...max(a.col, b.col)
        let rows = min(a.row, b.row)...max(a.row, b.row)
        func inside(_ cell: GridPoint) -> Bool { cols.contains(cell.col) && rows.contains(cell.row) }
        for placed in layout.buildings {
            guard let def = BuildingDefinition.find(placed.definitionID), !def.isProtocolCore else { continue }
            if placed.occupiedCells(definition: def).allSatisfy(inside) { groupSelection.insert(placed.id) }
        }
        for belt in layout.beltNetwork.belts where !belt.segments.isEmpty && belt.segments.allSatisfy({ inside($0.cell) }) {
            groupBeltSelection.insert(belt.id)
        }
    }

    /// 点一个建筑（没有建筑就看线）：没选中就加进来，选中了就移出；点空地不动
    func toggleGroupMember(at cell: GridPoint, slop: Int) {
        for radius in 0...max(0, slop) {
            let cells = radius == 0 ? [cell] : ring(around: cell, radius: radius)
            for c in cells {
                guard let hit = building(at: c) else { continue }
                guard !hit.def.isProtocolCore else { return }
                toggle(hit.placed.id, in: &groupSelection)
                return
            }
            for c in cells {
                guard let beltID = layout.beltNetwork.beltIDs(at: c).first else { continue }
                toggle(beltID, in: &groupBeltSelection)
                return
            }
        }
    }

    private func toggle(_ id: UUID, in set: inout Set<UUID>) {
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
    }

    func clearGroupSelection() {
        groupSelection.removeAll()
        groupBeltSelection.removeAll()
    }

    /// 整组移动时整条跟着平移的线：
    /// - 两头都接在组内建筑上的线（哪怕中间绕到框外）；
    /// - 选中的线，只要两头没有接在组外建筑上（接组外的那头要留在原地，交给改接逻辑）
    func beltsMovingWithGroup() -> Set<UUID> {
        // 每个口外面那一格 → 这个口属于哪台建筑
        var outOwner: [String: UUID] = [:]
        var inOwner: [String: UUID] = [:]
        for placed in layout.buildings {
            guard let def = BuildingDefinition.find(placed.definitionID) else { continue }
            for port in def.ports {
                let (cell, facing) = port.resolvedPosition(placed: placed, definition: def)
                let ext = cell + facing.outputOffset
                let key = "\(ext.col),\(ext.row),\(port.kind == .item ? LineType.belt.rawValue : LineType.pipe.rawValue)"
                if port.ioDirection == .output { outOwner[key] = placed.id } else { inOwner[key] = placed.id }
            }
        }
        func key(_ cell: GridPoint?, _ type: LineType) -> String {
            cell.map { "\($0.col),\($0.row),\(type.rawValue)" } ?? ""
        }
        var moving = Set<UUID>()
        for belt in layout.beltNetwork.belts {
            let headOwner = outOwner[key(belt.headCell, belt.lineType)]
            let tailOwner = inOwner[key(belt.tailCell, belt.lineType)]
            let headInGroup = headOwner.map(groupSelection.contains) ?? false
            let tailInGroup = tailOwner.map(groupSelection.contains) ?? false
            if headInGroup && tailInGroup {
                moving.insert(belt.id)
            } else if groupBeltSelection.contains(belt.id),
                      headOwner == nil || headInGroup, tailOwner == nil || tailInGroup {
                moving.insert(belt.id)
            }
        }
        return moving
    }

    /// 整组平移 delta 格能不能放：建筑和跟着走的线都不能出界，建筑不能压到组外建筑。
    /// 地图规则（比如取货口没贴好）不挡移动，放下后照常由地图冲突检查标红
    func canMoveGroup(by delta: GridPoint) -> Bool {
        let rules = layout.mapType.rules
        func outOfBounds(_ cell: GridPoint) -> Bool {
            cell.col < 0 || cell.row < 0 || cell.col >= rules.gridCols || cell.row >= rules.gridRows
        }
        var othersCells = Set<GridPoint>()
        for placed in layout.buildings where !groupSelection.contains(placed.id) {
            guard let def = BuildingDefinition.find(placed.definitionID) else { continue }
            othersCells.formUnion(placed.occupiedCells(definition: def))
        }
        for placed in groupBuildings {
            guard let def = BuildingDefinition.find(placed.definitionID) else { continue }
            for cell in placed.occupiedCells(definition: def) {
                let moved = cell + delta
                if outOfBounds(moved) || othersCells.contains(moved) { return false }
            }
        }
        let moving = beltsMovingWithGroup()
        for belt in layout.beltNetwork.belts where moving.contains(belt.id) {
            if belt.segments.contains(where: { outOfBounds($0.cell + delta) }) { return false }
        }
        return true
    }

    /// 整组平移；放不下就什么都不做
    func moveGroup(by delta: GridPoint) {
        guard delta != GridPoint(col: 0, row: 0), hasGroupSelection, canMoveGroup(by: delta) else { return }
        beginUndoGroup()
        defer { endUndoGroup() }

        let olds = groupBuildings
        let moving = beltsMovingWithGroup()

        for i in layout.buildings.indices where groupSelection.contains(layout.buildings[i].id) {
            layout.buildings[i].origin = layout.buildings[i].origin + delta
        }
        for i in layout.beltNetwork.belts.indices where moving.contains(layout.beltNetwork.belts[i].id) {
            for j in layout.beltNetwork.belts[i].segments.indices {
                layout.beltNetwork.belts[i].segments[j].cell = layout.beltNetwork.belts[i].segments[j].cell + delta
            }
        }

        // 一头接组外的线：改接到口的新位置，走不通就断开
        var broken = 0
        for old in olds {
            guard let def = BuildingDefinition.find(old.definitionID),
                  let moved = layout.buildings.first(where: { $0.id == old.id })
            else { continue }
            broken += reattachLines(old: old, new: moved, def: def, excluding: moving)
        }
        lineReattachMessage = broken > 0 ? "有 \(broken) 条线在新位置走不通，已经断开，需要重新接" : nil
        // 改接时断开的线不在了，选中里也去掉
        groupBeltSelection.formIntersection(Set(layout.beltNetwork.belts.map(\.id)))
        refreshStats()
    }

    /// 删除整组：选中的建筑（协议核心本来就不会被选进来）和选中的线
    func deleteGroup() {
        guard hasGroupSelection else { return }
        beginUndoGroup()
        defer { endUndoGroup() }
        let beltIDs = groupBeltSelection
        layout.beltNetwork.belts.removeAll { beltIDs.contains($0.id) }
        for placed in groupBuildings {
            guard let def = BuildingDefinition.find(placed.definitionID), !def.isProtocolCore else { continue }
            removeBuilding(placed, def: def)
        }
        clearGroupSelection()
        refreshStats()
    }
}
