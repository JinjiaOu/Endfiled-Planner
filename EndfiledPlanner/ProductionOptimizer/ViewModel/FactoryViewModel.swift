//
//  FactoryViewModel.swift
//  EndfiledPlanner
//
//  Created by Jinjia Ou on 4/3/26.
//

import SwiftUI
import Combine

// MARK: - 编辑模式
enum FactoryEditMode: Equatable {
    case select             // 选择/查看
    case place(BuildingDefinition)  // 放置建筑
    case belt               // 连接传送带
    case pipe                // 连接管道
    case erase              // 删除
}

class FactoryViewModel: ObservableObject {

    // MARK: - 状态
    @Published var layout: FactoryLayout = FactoryGridModel.load()
    @Published var editMode: FactoryEditMode = .select
    @Published var selectedBuildingID: UUID? = nil
    @Published var hoverCell: GridPoint? = nil          // 当前悬停格（放置预览）
    @Published var pendingRotation: BuildingRotation = .up
    @Published var beltStart: GridPoint? = nil          // 传送带起点
    @Published var pendingDropCell: GridPoint? = nil    // 拖拽放置落点
    @Published var showSaveConfirm = false
    @Published var stats: FactoryGridModel.ProductionStats

    // 配方数据：按机器名分组去重，PlacedBuilding.selectedRecipeIndex 就是这份列表里的下标
    let machineRecipes: [String: [Recipe]]

    init() {
        machineRecipes = RecipeViewModel().recipesByMachine()
        let loaded = FactoryGridModel.load()
        layout = loaded
        stats = FactoryGridModel.analyze(layout: loaded, machineRecipes: machineRecipes)
    }

    /// 这台建筑（按 name 匹配）可选的配方列表
    func availableRecipes(for def: BuildingDefinition) -> [Recipe] {
        machineRecipes[def.name] ?? []
    }

    /// 设置/切换某台已放置建筑使用的配方
    func selectRecipe(_ index: Int?, for buildingID: UUID) {
        guard let idx = layout.buildings.firstIndex(where: { $0.id == buildingID }) else { return }
        layout.buildings[idx].selectedRecipeIndex = index
        refreshStats()
    }

    // MARK: - 网格点击处理
    func handleTap(at cell: GridPoint) {
        switch editMode {
        case .select:
            selectBuilding(at: cell)

        case .place(let def):
            placeBuilding(def, at: cell)

        case .belt, .pipe:
            break   // 由拖拽手势处理，点击不响应

        case .erase:
            eraseAt(cell: cell)
        }
    }

    // MARK: - 放置建筑
    func placeBuilding(_ def: BuildingDefinition, at cell: GridPoint) {
        guard FactoryGridModel.canPlace(
            definition: def,
            at: cell,
            rotation: pendingRotation,
            existing: layout.buildings
        ) else { return }

        let placed = PlacedBuilding(definitionID: def.id, origin: cell, rotation: pendingRotation)
        layout.buildings.append(placed)
        refreshStats()
    }

    // MARK: - 选择建筑
    func selectBuilding(at cell: GridPoint) {
        for placed in layout.buildings {
            guard let def = BuildingDefinition.find(placed.definitionID) else { continue }
            let cells = placed.occupiedCells(definition: def)
            if cells.contains(cell) {
                selectedBuildingID = placed.id
                return
            }
        }
        selectedBuildingID = nil
    }

    // MARK: - 旋转已选建筑
    func rotateSelected() {
        guard let id = selectedBuildingID,
              let idx = layout.buildings.firstIndex(where: { $0.id == id })
        else {
            // 在放置模式下旋转预览
            pendingRotation = pendingRotation.next
            return
        }
        layout.buildings[idx].rotation = layout.buildings[idx].rotation.next
    }

    // MARK: - 传送带 / 管道（拖拽绘制，共用同一套路由逻辑）
    @Published var beltPreviewSegments: [BeltSegment] = []
    @Published var beltDragCurrentPoint: CGPoint? = nil
    // 拖拽过程中吸附到的建筑端口（用于高亮 + 落地时精确对齐）
    @Published var activeSnap: PortSnapCandidate? = nil

    /// 当前编辑模式对应的线路类型
    var activeLineType: LineType {
        if case .pipe = editMode { return .pipe }
        return .belt
    }

    func handleBeltDragChanged(at cell: GridPoint, point: CGPoint) {
        if beltStart == nil {
            beltStart = cell
        }
        beltDragCurrentPoint = point
        let snap = findNearbyPort(for: activeLineType, near: cell)
        activeSnap = snap
        if let snap, snap.isKindMatch, !snap.isOccupied {
            beltPreviewSegments = routedSegments(from: beltStart!, toPort: snap, currentPoint: point, lineType: activeLineType)
        } else {
            beltPreviewSegments = buildBeltSegments(from: beltStart!, to: cell, currentPoint: point, lineType: activeLineType)
        }
    }

    func handleBeltDragEnded(at cell: GridPoint) {
        guard let start = beltStart else { return }
        let snap = findNearbyPort(for: activeLineType, near: cell)
        let segs: [BeltSegment]
        if let snap, snap.isKindMatch, !snap.isOccupied {
            segs = routedSegments(from: start, toPort: snap, currentPoint: beltDragCurrentPoint, lineType: activeLineType)
        } else {
            segs = buildBeltSegments(from: start, to: cell, currentPoint: beltDragCurrentPoint, lineType: activeLineType)
        }
        beltStart = nil
        beltDragCurrentPoint = nil
        beltPreviewSegments = []
        activeSnap = nil
        guard !segs.isEmpty else { return }
        commitSegments(segs)
    }

    // MARK: - 建筑端口吸附

    struct PortSnapCandidate {
        let port: BuildingPort
        let portCell: GridPoint       // 端口本身所在的建筑格
        let externalCell: GridPoint   // 端口外面紧邻的格子，传送带/管道应该落在这一格
        let facing: BuildingRotation  // 这条边朝外的方向（旋转后）
        let isKindMatch: Bool         // 口的类型（普通口/管道口）和当前画的线是否匹配
        let isOccupied: Bool          // 这个端口是不是已经被别的线接了
    }

    private func opposite(_ d: BuildingRotation) -> BuildingRotation {
        BuildingRotation(rawValue: (d.rawValue + 2) % 4) ?? d
    }

    /// 某个外部格子是不是已经有一条带的头/尾停在这里（近似：只要有带的端点落在这一格，就认为端口被占用）
    private func isPortOccupied(externalCell: GridPoint) -> Bool {
        layout.beltNetwork.belts.contains {
            $0.headCell == externalCell || $0.tailCell == externalCell
        }
    }

    /// 在 cell 周围找一个"外部连接格恰好是 cell"的建筑端口
    /// （不管类型匹不匹配都先找到，方不匹配/被占用的情况留给调用方决定怎么提示）
    func findNearbyPort(for lineType: LineType, near cell: GridPoint) -> PortSnapCandidate? {
        let wantedKind: PortKind = lineType == .belt ? .item : .pipe
        for placed in layout.buildings {
            guard let def = BuildingDefinition.find(placed.definitionID) else { continue }
            for port in def.ports {
                let (portCell, facing) = port.resolvedPosition(placed: placed, definition: def)
                let external = GridPoint(col: portCell.col + facing.outputOffset.col,
                                          row: portCell.row + facing.outputOffset.row)
                guard external == cell else { continue }
                return PortSnapCandidate(
                    port: port,
                    portCell: portCell,
                    externalCell: external,
                    facing: facing,
                    isKindMatch: port.kind == wantedKind,
                    isOccupied: isPortOccupied(externalCell: external)
                )
            }
        }
        return nil
    }

    /// 从 start 拖到某个端口：先按正常 L 形路由走到端口的"前一格"，
    /// 最后强制补一格精确对齐端口方向的段，保证不管手指怎么拖，落地那一格朝向都是对的
    private func routedSegments(from start: GridPoint, toPort snap: PortSnapCandidate,
                                currentPoint: CGPoint?, lineType: LineType) -> [BeltSegment] {
        // 端口朝外方向是 facing；出口是往外流（沿 facing），入口是往里流（逆着 facing）
        let finalDir = snap.port.ioDirection == .output ? snap.facing : opposite(snap.facing)
        let approachCell = GridPoint(col: snap.externalCell.col - finalDir.outputOffset.col,
                                     row: snap.externalCell.row - finalDir.outputOffset.row)

        var segs: [BeltSegment]
        if start == snap.externalCell || start == approachCell {
            segs = []
        } else {
            segs = buildBeltSegments(from: start, to: approachCell, currentPoint: currentPoint, lineType: lineType)
        }
        let finalAxis: BeltAxis = (finalDir == .up || finalDir == .down) ? .vertical : .horizontal
        segs.append(BeltSegment(cell: snap.externalCell, axis: finalAxis,
                                fromDir: finalDir.outputOffset, toDir: finalDir.outputOffset, lineType: lineType))
        return segs
    }

    /// L 形路径生成：根据手指像素偏移动态决定先走哪个轴
    func buildBeltSegments(from start: GridPoint, to end: GridPoint,
                           currentPoint: CGPoint? = nil, lineType: LineType = .belt) -> [BeltSegment] {
        guard start != end else { return [] }
        let dc = end.col - start.col
        let dr = end.row - start.row
        let colDir = dc == 0 ? 0 : (dc > 0 ? 1 : -1)
        let rowDir = dr == 0 ? 0 : (dr > 0 ? 1 : -1)

        if dc == 0 { return makeVertical(from: start, dr: dr, rowDir: rowDir, lineType: lineType) }
        if dr == 0 { return makeHorizontal(from: start, dc: dc, colDir: colDir, lineType: lineType) }

        let hFirst: Bool
        if let pt = currentPoint {
            hFirst = abs(pt.x) >= abs(pt.y)
        } else {
            hFirst = true
        }

        if hFirst {
            let corner = GridPoint(col: end.col, row: start.row)
            return makeHorizontal(from: start, dc: dc, colDir: colDir, lineType: lineType)
                 + makeVertical(from: corner, dr: dr, rowDir: rowDir, lineType: lineType)
        } else {
            let corner = GridPoint(col: start.col, row: end.row)
            return makeVertical(from: start, dr: dr, rowDir: rowDir, lineType: lineType)
                 + makeHorizontal(from: corner, dc: dc, colDir: colDir, lineType: lineType)
        }
    }

    private func makeHorizontal(from start: GridPoint, dc: Int, colDir: Int, lineType: LineType) -> [BeltSegment] {
        var segs: [BeltSegment] = []
        var cur = start
        for _ in 0..<abs(dc) {
            segs.append(BeltSegment(cell: cur, axis: .horizontal,
                fromDir: GridPoint(col: colDir, row: 0),
                toDir:   GridPoint(col: colDir, row: 0),
                lineType: lineType))
            cur = GridPoint(col: cur.col + colDir, row: cur.row)
        }
        return segs
    }

    private func makeVertical(from start: GridPoint, dr: Int, rowDir: Int, lineType: LineType) -> [BeltSegment] {
        var segs: [BeltSegment] = []
        var cur = start
        for _ in 0..<abs(dr) {
            segs.append(BeltSegment(cell: cur, axis: .vertical,
                fromDir: GridPoint(col: 0, row: rowDir),
                toDir:   GridPoint(col: 0, row: rowDir),
                lineType: lineType))
            cur = GridPoint(col: cur.col, row: cur.row + rowDir)
        }
        return segs
    }

    /// 把新段放进 BeltNetwork
    /// 规则：
    ///   - 新带起点格 == 某已有【同类型】带的 tailCell → 追加进那条带（衔接，圆角转弯）
    ///   - 否则新建一条带
    ///   - 过滤完全重叠的段（同格+同轴+同方向+同类型）
    ///   - 允许十字交叉（同格异轴），也允许传送带和管道在同格共存（同格同轴不同类型）
    private func commitSegments(_ newSegs: [BeltSegment]) {
        guard !newSegs.isEmpty else { return }
        let lineType = newSegs[0].lineType

        // 去重：过滤掉已存在的完全相同段（类型也要匹配，belt 和 pipe 不互相视为重复）
        let existingKeys = Set(layout.beltNetwork.allSegments.map {
            "\($0.cell.col),\($0.cell.row),\($0.axis.rawValue),\($0.toDir.col),\($0.toDir.row),\($0.lineType.rawValue)"
        })
        let filtered = newSegs.filter { seg in
            let key = "\(seg.cell.col),\(seg.cell.row),\(seg.axis.rawValue),\(seg.toDir.col),\(seg.toDir.row),\(seg.lineType.rawValue)"
            return !existingKeys.contains(key)
        }
        guard !filtered.isEmpty else { return }

        let startCell = filtered[0].cell
        let startKey  = "\(startCell.col),\(startCell.row)"
        let endCell   = filtered[filtered.count - 1].cell
        let endKey    = "\(endCell.col),\(endCell.row)"

        // 只在同类型（belt 接 belt / pipe 接 pipe）的带之间做衔接
        // 1. 新带起点 在某已有带末端范围内 → append 到那条带尾部
        if let idx = layout.beltNetwork.belts.firstIndex(where: {
            $0.lineType == lineType && $0.tailNeighborhood.contains(startKey)
        }) {
            layout.beltNetwork.belts[idx].segments.append(contentsOf: filtered)
        }
        // 2. 新带终点 在某已有带起点范围内 → prepend 到那条带头部
        else if let idx = layout.beltNetwork.belts.firstIndex(where: {
            $0.lineType == lineType && $0.headNeighborhood.contains(endKey)
        }) {
            layout.beltNetwork.belts[idx].segments.insert(contentsOf: filtered, at: 0)
        }
        // 3. 都不匹配 → 新建一条带
        else {
            layout.beltNetwork.belts.append(Belt(segments: filtered))
        }
    }

    /// 建筑重叠格子 key 列表
    func blockedCellKeys(for segs: [BeltSegment]) -> [String] {
        let occupied = occupiedBuildingCellKeys()
        return segs.compactMap { seg -> String? in
            let key = "\(seg.cell.col),\(seg.cell.row)"
            return occupied.contains(key) ? key : nil
        }
    }

    func occupiedBuildingCellKeys() -> Set<String> {
        Set(layout.buildings.flatMap { placed -> [String] in
            guard let def = BuildingDefinition.find(placed.definitionID) else { return [] }
            return placed.occupiedCells(definition: def).map { "\($0.col),\($0.row)" }
        })
    }

    // MARK: - 删除（带确认弹窗）
    @Published var pendingEraseBuilding: (placed: PlacedBuilding, def: BuildingDefinition)? = nil
    @Published var pendingEraseCell: GridPoint? = nil
    // 十字格可能属于多条带，记录所有候选带 ID
    @Published var pendingEraseBeltIDs: [UUID] = []

    func eraseAt(cell: GridPoint) {
        // 优先检测建筑
        for placed in layout.buildings {
            guard let def = BuildingDefinition.find(placed.definitionID) else { continue }
            if placed.occupiedCells(definition: def).contains(cell) {
                pendingEraseBuilding = (placed, def)
                return
            }
        }
        // 检测传送带/管道
        let ids = layout.beltNetwork.beltIDs(at: cell)
        if !ids.isEmpty {
            pendingEraseCell = cell
            pendingEraseBeltIDs = ids
        }
    }

    /// 这一格上实际有哪些线路类型（传送带/管道各自同格共存时会有两种）
    var pendingEraseLineTypes: [LineType] {
        guard let cell = pendingEraseCell else { return [] }
        let types = Set(layout.beltNetwork.allSegments
            .filter { $0.cell.col == cell.col && $0.cell.row == cell.row }
            .map { $0.lineType })
        return LineType.allCases.filter { types.contains($0) }
    }

    /// 确认删除建筑（同时移除其格子上的所有传送带段）
    func confirmEraseBuilding() {
        guard let target = pendingEraseBuilding else { return }
        let cells = target.placed.occupiedCells(definition: target.def)
        layout.buildings.removeAll { $0.id == target.placed.id }
        for cell in cells { removeCellFromAllBelts(cell, lineType: nil) }
        pendingEraseBuilding = nil
        refreshStats()
    }

    /// 确认删除这一格（lineType 为 nil 就是"两个都删"，指定类型就只删那一种）
    func confirmEraseCell(lineType: LineType? = nil) {
        guard let cell = pendingEraseCell else { return }
        removeCellFromAllBelts(cell, lineType: lineType)
        pendingEraseCell = nil
        pendingEraseBeltIDs = []
    }

    /// 确认删除整条带（按 Belt ID 精确删，不影响十字穿插/同格共存的其他带；
    /// lineType 为 nil 就是这一格命中的带全删，指定类型就只删那一种）
    func confirmEraseWholeBelt(lineType: LineType? = nil) {
        guard !pendingEraseBeltIDs.isEmpty else { return }
        let ids = Set(pendingEraseBeltIDs)
        layout.beltNetwork.belts.removeAll {
            ids.contains($0.id) && (lineType == nil || $0.lineType == lineType)
        }
        pendingEraseCell = nil
        pendingEraseBeltIDs = []
    }

    func cancelErase() {
        pendingEraseBuilding = nil
        pendingEraseCell = nil
        pendingEraseBeltIDs = []
    }

    /// 从所有带中移除某格的段（可选只针对某一种线路类型），带若因此断裂则分裂成子带
    private func removeCellFromAllBelts(_ cell: GridPoint, lineType: LineType?) {
        var newBelts: [Belt] = []
        for belt in layout.beltNetwork.belts {
            if let lineType, belt.lineType != lineType {
                // 不是要删的类型，整条原样保留
                newBelts.append(belt)
                continue
            }
            let remaining = belt.segments.filter {
                !($0.cell.col == cell.col && $0.cell.row == cell.row)
            }
            // 把 remaining 按连续性分裂成子带
            let subBelts = splitIntoSubBelts(remaining)
            newBelts.append(contentsOf: subBelts)
        }
        layout.beltNetwork.belts = newBelts
    }

    /// 把有序段列表按连续性（相邻段格子直接相邻）分裂成若干子带
    private func splitIntoSubBelts(_ segments: [BeltSegment]) -> [Belt] {
        guard !segments.isEmpty else { return [] }
        var result: [Belt] = []
        var current: [BeltSegment] = [segments[0]]
        for i in 1..<segments.count {
            let prev = segments[i - 1]
            let curr = segments[i]
            // 判断是否连续：prev 出口格 == curr 所在格
            let prevOut = GridPoint(col: prev.cell.col + prev.toDir.col,
                                    row: prev.cell.row + prev.toDir.row)
            if prevOut == curr.cell {
                current.append(curr)
            } else {
                if !current.isEmpty { result.append(Belt(segments: current)) }
                current = [curr]
            }
        }
        if !current.isEmpty { result.append(Belt(segments: current)) }
        return result
    }

    func deleteSelected() {
        guard let id = selectedBuildingID,
              let placed = layout.buildings.first(where: { $0.id == id }),
              let def = BuildingDefinition.find(placed.definitionID)
        else { return }

        let cells = placed.occupiedCells(definition: def)
        layout.buildings.removeAll { $0.id == id }
        for cell in cells { removeCellFromAllBelts(cell, lineType: nil) }
        selectedBuildingID = nil
        refreshStats()
    }

    // MARK: - 保存/清空
    func saveLayout() {
        var toSave = layout
        toSave.savedAt = .now
        FactoryGridModel.save(toSave)
        showSaveConfirm = true
    }

    func clearLayout() {
        layout = .empty
        selectedBuildingID = nil
        beltStart = nil
        beltPreviewSegments = []
        pendingEraseBeltIDs = []
        FactoryGridModel.clear()
        refreshStats()
    }

    // MARK: - 查询
    func building(at cell: GridPoint) -> (placed: PlacedBuilding, def: BuildingDefinition)? {
        for placed in layout.buildings {
            guard let def = BuildingDefinition.find(placed.definitionID) else { continue }
            if placed.occupiedCells(definition: def).contains(cell) {
                return (placed, def)
            }
        }
        return nil
    }

    func canPlaceAt(_ def: BuildingDefinition, cell: GridPoint) -> Bool {
        FactoryGridModel.canPlace(
            definition: def,
            at: cell,
            rotation: pendingRotation,
            existing: layout.buildings
        )
    }

    var selectedPlaced: PlacedBuilding? {
        layout.buildings.first { $0.id == selectedBuildingID }
    }

    var selectedDefinition: BuildingDefinition? {
        guard let p = selectedPlaced else { return nil }
        return BuildingDefinition.find(p.definitionID)
    }

    private func refreshStats() {
        stats = FactoryGridModel.analyze(layout: layout, machineRecipes: machineRecipes)
    }
}
