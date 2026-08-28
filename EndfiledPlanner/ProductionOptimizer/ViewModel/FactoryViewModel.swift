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
    // 取线出口能选的材料：recipes.txt 里所有固体产物
    let solidMaterials: [String]

    init() {
        let recipeVM = RecipeViewModel()
        machineRecipes = recipeVM.recipesByMachine()
        solidMaterials = recipeVM.solidOutputNames()
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

    // MARK: - 地图
    /// 切换地图会清空当前布局——两张地图的仓库取线规则完全不同（贴边 vs 连基段），
    /// 建筑/线路留着也大概率不合法，不如直接清干净重新摆
    func switchMap(to mapType: MapType) {
        layout = .empty
        layout.mapType = mapType
        selectedBuildingID = nil
        beltStart = nil
        beltPreviewSegments = []
        pendingEraseBeltIDs = []
        FactoryGridModel.clear()
        refreshStats()
    }

    /// 仓库取货口/存货口自动定向，不用用户自己转：优先选一个能让当前位置直接合法摆放的朝向
    /// （四号谷地是贴地图边，武陵是贴基段，两边都要求长边贴死+口朝对方反方向开），
    /// 避免拖拽路径不同导致预览来回跳；还没拖到合法位置时（比如刚从建造面板拿起来）
    /// 才退回一个大概方向，仅供预览用
    func autoOrientedRotation(for def: BuildingDefinition, at cell: GridPoint) -> BuildingRotation? {
        guard BuildingDefinition.warehousePortIDs.contains(def.id) else { return nil }
        for candidate in BuildingRotation.allCases {
            if FactoryGridModel.canPlace(definition: def, at: cell, rotation: candidate,
                                          existing: layout.buildings, mapType: layout.mapType) {
                return candidate
            }
        }
        switch layout.mapType {
        case .valley4:
            return cell.row <= cell.col ? .down : .right
        case .wuling:
            // 基段和源桩都能贴，猜方向时两种都算候选
            let dockTargets = layout.buildings.filter {
                $0.definitionID == BuildingDefinition.warehouseBaseSegmentID ||
                $0.definitionID == BuildingDefinition.warehouseSourceID
            }
            guard let nearest = nearestCell(to: cell, among: dockTargets) else { return nil }
            return direction(from: cell, toward: nearest)
        }
    }

    private func nearestCell(to cell: GridPoint, among buildings: [PlacedBuilding]) -> GridPoint? {
        var best: GridPoint? = nil
        var bestDist = Int.max
        for placed in buildings {
            guard let def = BuildingDefinition.find(placed.definitionID) else { continue }
            for c in placed.occupiedCells(definition: def) {
                let d = abs(c.col - cell.col) + abs(c.row - cell.row)
                if d < bestDist { bestDist = d; best = c }
            }
        }
        return best
    }

    private func direction(from cell: GridPoint, toward target: GridPoint) -> BuildingRotation {
        let dc = target.col - cell.col
        let dr = target.row - cell.row
        if abs(dr) >= abs(dc) {
            return dr >= 0 ? .down : .up
        } else {
            return dc >= 0 ? .right : .left
        }
    }

    // MARK: - 取线出口
    /// 设置/清空某个取线出口当前取货的材料
    func setOutletMaterial(_ material: String?, for buildingID: UUID) {
        guard let idx = layout.buildings.firstIndex(where: { $0.id == buildingID }) else { return }
        layout.buildings[idx].outletMaterial = material
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
            existing: layout.buildings,
            mapType: layout.mapType
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

    /// 给渲染层用：这台已放置建筑的某个端口，现在有没有接上传送带/管道
    func isPortConnected(_ port: BuildingPort, placed: PlacedBuilding, definition: BuildingDefinition) -> Bool {
        let (cell, facing) = port.resolvedPosition(placed: placed, definition: definition)
        let external = GridPoint(col: cell.col + facing.outputOffset.col, row: cell.row + facing.outputOffset.row)
        return isPortOccupied(externalCell: external)
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
    ///   - 同一格、同一轴、同一类型的线不能重复摆放，哪怕方向相反也算冲突（物理上不能叠在一起）
    ///   - 同类型异轴真交叉（属于两条不同的带）自动放一个物流桥/管道桥；
    ///     同一条带自己拐弯不算交叉，衔接逻辑已经把它接成一条带了
    ///   - 不同类型（belt/pipe）随便共存，不算冲突也不用放桥
    private func commitSegments(_ newSegs: [BeltSegment]) {
        guard !newSegs.isEmpty else { return }
        let lineType = newSegs[0].lineType
        let existingSegs = layout.beltNetwork.allSegments

        // 同格+同轴+同类型 = 冲突，不管方向是不是相反，直接不让放这一段
        // （这个 key 里不含 toDir，所以已存在的同向重复段也会被这条规则一起挡掉，等价于原来的去重逻辑）
        let conflictKeys = Set(existingSegs.map {
            "\($0.cell.col),\($0.cell.row),\($0.axis.rawValue),\($0.lineType.rawValue)"
        })
        let filtered = newSegs.filter { seg in
            let key = "\(seg.cell.col),\(seg.cell.row),\(seg.axis.rawValue),\(seg.lineType.rawValue)"
            return !conflictKeys.contains(key)
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

        // 交叉检测放在合并【之后】：只有当这一格现在属于两条不同 id 的同类型带，
        // 才是真交叉（自己拐弯会被上面的衔接逻辑合并成同一条带，id 只有一个，不会误判）
        for seg in filtered {
            autoPlaceBridgeIfCrossing(at: seg.cell, lineType: seg.lineType)
        }
        refreshStats()
    }

    private func autoPlaceBridgeIfCrossing(at cell: GridPoint, lineType: LineType) {
        let beltIDsHere = Set(layout.beltNetwork.belts
            .filter { belt in
                belt.lineType == lineType &&
                belt.segments.contains { $0.cell.col == cell.col && $0.cell.row == cell.row }
            }
            .map { $0.id })
        guard beltIDsHere.count > 1 else { return }   // 只属于一条带，是自己拐弯不是交叉
        autoPlaceBridge(at: cell, lineType: lineType)
    }

    /// 物流桥/管道桥的建筑 id，渲染时要把它们从"挡路"判定里排除掉——
    /// 交叉点本来就是让线穿过去的，不该被当成建筑冲突标红
    static let bridgeBuildingIDs: Set<String> = ["log_connector", "log_pipe_connector"]

    /// 同类型十字交叉自动放的物流桥/管道桥：1x1 占地，四个方向都有入口和出口，
    /// 已经占了建筑或者放不下就跳过，不强行覆盖
    private func autoPlaceBridge(at cell: GridPoint, lineType: LineType) {
        let bridgeID = lineType == .belt ? "log_connector" : "log_pipe_connector"
        guard let def = BuildingDefinition.find(bridgeID) else { return }
        let alreadyBuilt = layout.buildings.contains { placed in
            guard let d = BuildingDefinition.find(placed.definitionID) else { return false }
            return placed.occupiedCells(definition: d).contains(cell)
        }
        guard !alreadyBuilt else { return }
        guard FactoryGridModel.canPlace(definition: def, at: cell, rotation: .up, existing: layout.buildings, mapType: layout.mapType) else { return }
        layout.buildings.append(PlacedBuilding(definitionID: bridgeID, origin: cell, rotation: .up))
    }

    /// 传送带/管道渲染用的"挡路格子"：普通建筑挡，但物流桥/管道桥这类交叉节点不挡
    /// （它们本来就是给线穿过去用的）
    func lineBlockingCellKeys() -> Set<String> {
        Set(layout.buildings
            .filter { !FactoryViewModel.bridgeBuildingIDs.contains($0.definitionID) }
            .flatMap { placed -> [String] in
                guard let def = BuildingDefinition.find(placed.definitionID) else { return [] }
                return placed.occupiedCells(definition: def).map { "\($0.col),\($0.row)" }
            })
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
            existing: layout.buildings,
            mapType: layout.mapType
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
