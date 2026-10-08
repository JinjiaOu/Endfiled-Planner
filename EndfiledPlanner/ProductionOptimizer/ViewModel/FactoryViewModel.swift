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
    case boxSelect          // 框选：拖框选一组建筑，整组移动/删除
}

class FactoryViewModel: ObservableObject {

    // MARK: - 状态
    @Published var layout: FactoryLayout = FactoryGridModel.load() {
        didSet { recordUndo(previous: oldValue) }
    }
    @Published var editMode: FactoryEditMode = .select {
        didSet {
            guard editMode != oldValue else { return }
            // 进框选时清掉单选；离开框选时清掉整组选中
            if editMode == .boxSelect { clearSelection() } else { clearGroupSelection() }
            // 换工具就放弃正在摆的布局
            pendingPlacement = nil
        }
    }
    /// 框选模式下选中的一组建筑（协议核心不参与）
    @Published var groupSelection: Set<UUID> = []
    /// 框选模式下选中的线（整条都在框里的传送带/管道）
    @Published var groupBeltSelection: Set<UUID> = []
    /// 正在往画布上摆的"我的布局"（虚影），nil = 没在摆
    @Published var pendingPlacement: PendingPlacement? = nil
    @Published var selectedBuildingID: UUID? = nil {
        didSet { if selectedBuildingID != nil { selectedBeltID = nil } }
    }
    /// 选中的传送带/管道（跟 selectedBuildingID 互斥），selectedBeltCell 是点中的那一格（删"这一格"用）
    @Published var selectedBeltID: UUID? = nil {
        didSet { if selectedBeltID != nil { selectedBuildingID = nil } }
    }
    @Published var selectedBeltCell: GridPoint? = nil

    // MARK: - 撤销 / 重做
    // 布局每次改动都记一份改动前的快照；同一次操作里连续好几步赋值（比如删建筑顺带删线）
    // 只在这一轮 runloop 结束时合并成一步
    @Published private(set) var undoStack: [FactoryLayout] = []
    @Published private(set) var redoStack: [FactoryLayout] = []
    private var pendingUndoSnapshot: FactoryLayout? = nil
    private var isRestoringHistory = false
    private static let undoLimit = 60
    @Published var hoverCell: GridPoint? = nil          // 当前悬停格（放置预览）
    @Published var pendingRotation: BuildingRotation = .up
    @Published var beltStart: GridPoint? = nil          // 传送带起点
    @Published var pendingDropCell: GridPoint? = nil    // 拖拽放置落点
    @Published var showSaveConfirm = false
    /// 保存提示条上的文字（保存画布 / 存为我的布局共用一个提示条）
    @Published var toastText = "画布已保存"
    /// 详情面板点了"移动"后，下一次点网格就把这台建筑挪过去（点的格子是新的左上角）
    @Published var movingBuildingID: UUID? = nil
    @Published var moveFailedMessage: String? = nil
    @Published var stats: FactoryGridModel.ProductionStats

    // 配方数据：按建筑 id 分组，PlacedBuilding 记的是其中的配方 ID
    let machineRecipes: [String: [Recipe]]
    // 取线出口能选的材料：配方产物里所有固体
    let solidMaterials: [ItemInfo]
    // 管道准入口过滤能选的：配方产物里所有液体和气体
    let fluidMaterials: [ItemInfo]

    /// >0 时（比如删除工具按住划过的整个过程）所有改动合并成一步，endUndoGroup 时才入栈
    private var undoGroupDepth = 0

    private func recordUndo(previous: FactoryLayout) {
        guard !isRestoringHistory, pendingUndoSnapshot == nil else { return }
        pendingUndoSnapshot = previous
        guard undoGroupDepth == 0 else { return }
        DispatchQueue.main.async { [weak self] in self?.commitPendingUndo() }
    }

    private func commitPendingUndo() {
        guard undoGroupDepth == 0, let snapshot = pendingUndoSnapshot else { return }
        pendingUndoSnapshot = nil
        undoStack.append(snapshot)
        if undoStack.count > Self.undoLimit { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    func beginUndoGroup() { undoGroupDepth += 1 }

    func endUndoGroup() {
        undoGroupDepth = max(0, undoGroupDepth - 1)
        commitPendingUndo()
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(layout)
        restore(previous)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(layout)
        restore(next)
    }

    private func restore(_ snapshot: FactoryLayout) {
        isRestoringHistory = true
        layout = snapshot
        isRestoringHistory = false
        if let id = selectedBuildingID, !layout.buildings.contains(where: { $0.id == id }) { selectedBuildingID = nil }
        if let id = selectedBeltID, !layout.beltNetwork.belts.contains(where: { $0.id == id }) { clearBeltSelection() }
        let existingIDs = Set(layout.buildings.map(\.id))
        groupSelection.formIntersection(existingIDs)
        groupBeltSelection.formIntersection(Set(layout.beltNetwork.belts.map(\.id)))
        cancelMoving()
        refreshStats()
    }

    init() {
        let recipeVM = RecipeViewModel()
        machineRecipes = recipeVM.recipesByMachine()
        solidMaterials = recipeVM.solidOutputs()
        fluidMaterials = recipeVM.fluidOutputs()
        var loaded = FactoryGridModel.load()
        FactoryGridModel.ensureProtocolCore(in: &loaded)
        layout = loaded
        stats = FactoryGridModel.analyze(layout: loaded, machineRecipes: machineRecipes)
        // 启动时读档那一下不算一步操作
        DispatchQueue.main.async { [weak self] in
            self?.pendingUndoSnapshot = nil
            self?.undoStack.removeAll()
        }
    }

    /// 这台建筑可选的配方列表
    func availableRecipes(for def: BuildingDefinition) -> [Recipe] {
        FactoryGridModel.recipes(for: def, in: machineRecipes)
    }

    /// 设置/切换某台已放置建筑使用的配方
    func selectRecipe(_ recipeID: String?, for buildingID: UUID) {
        guard let idx = layout.buildings.firstIndex(where: { $0.id == buildingID }) else { return }
        layout.buildings[idx].selectedRecipeID = recipeID
        refreshStats()
    }

    // MARK: - 反应池 / 扩容反应池：多配方 + 自我供给
    /// 勾选/取消某条配方（多选，反应池/扩容反应池专用）
    func toggleRecipe(_ recipeID: String, for buildingID: UUID) {
        guard let idx = layout.buildings.firstIndex(where: { $0.id == buildingID }) else { return }
        if layout.buildings[idx].selectedRecipeIDs.contains(recipeID) {
            layout.buildings[idx].selectedRecipeIDs.remove(recipeID)
        } else {
            layout.buildings[idx].selectedRecipeIDs.insert(recipeID)
        }
        refreshStats()
    }

    /// 净产出物品选择哪个物理输出口（同类型口有 2 种以上净产物时才需要手动指定）
    func setOutputPortAssignment(item: String, portIndex: Int, for buildingID: UUID) {
        guard let idx = layout.buildings.firstIndex(where: { $0.id == buildingID }) else { return }
        // 同一个口只能对应一种物品，先清掉这个口原来指定的物品，再清掉这个物品原来指定的口
        layout.buildings[idx].outputPortAssignments = layout.buildings[idx].outputPortAssignments.filter {
            $0.key != portIndex && $0.value != item
        }
        layout.buildings[idx].outputPortAssignments[portIndex] = item
        refreshStats()
    }

    func clearOutputPortAssignment(item: String, for buildingID: UUID) {
        guard let idx = layout.buildings.firstIndex(where: { $0.id == buildingID }) else { return }
        layout.buildings[idx].outputPortAssignments = layout.buildings[idx].outputPortAssignments.filter { $0.value != item }
        refreshStats()
    }

    /// 选中建筑当前的自我供给分析（净流量、是否超容量/超输出上限），非反应池类建筑返回 nil
    func selfSupplyAnalysis(for placed: PlacedBuilding, definition: BuildingDefinition) -> FlowSimulator.SelfSupplyAnalysis? {
        guard definition.isMultiRecipeMachine else { return nil }
        let recipes = availableRecipes(for: definition)
        let selected = recipes.filter { placed.selectedRecipeIDs.contains($0.id) }
        guard !selected.isEmpty else { return nil }
        return FlowSimulator.analyzeSelfSupply(recipes: selected, capacity: definition.multiRecipeItemCapacity)
    }

    // MARK: - 地图
    /// 切换地图会清空当前布局——两张地图的仓库取线规则完全不同（贴边 vs 连基段），
    /// 建筑/线路留着也大概率不合法，不如直接清干净重新摆
    func switchMap(to mapType: MapType) {
        layout = .empty
        layout.mapType = mapType
        // 新地图不能用管道时，正拿着的管道工具退回选择
        if editMode == .pipe && !mapType.rules.allowsPipes { editMode = .select }
        FactoryGridModel.ensureProtocolCore(in: &layout)
        selectedBuildingID = nil
        beltStart = nil
        beltPreviewSegments = []
        clearSelection()
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
        switch layout.mapType.rules.warehouseLine {
        case .perimeter:
            return cell.row <= cell.col ? .down : .right
        case .busDock:
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

    // MARK: - 准入口限速
    /// 设置物品/管道准入口的最大流速（个/分钟），nil = 不额外限速
    func setFlowLimit(_ perMin: Double?, for buildingID: UUID) {
        guard let idx = layout.buildings.firstIndex(where: { $0.id == buildingID }) else { return }
        layout.buildings[idx].flowLimitPerMin = perMin
        refreshStats()
    }

    /// 设置物品/管道准入口只放行哪种物品（itemId），nil = 全部通过
    func setFilterItem(_ itemID: String?, for buildingID: UUID) {
        guard let idx = layout.buildings.firstIndex(where: { $0.id == buildingID }) else { return }
        layout.buildings[idx].filterItemID = itemID
        refreshStats()
    }

    // MARK: - 协议核心出货口
    /// 设置/清空协议核心某个出货口出的材料（portIndex 是 BuildingDefinition.ports 的下标，itemID 是 itemId）
    func setPortMaterial(_ itemID: String?, portIndex: Int, for buildingID: UUID) {
        guard let idx = layout.buildings.firstIndex(where: { $0.id == buildingID }) else { return }
        layout.buildings[idx].portMaterialIDs[portIndex] = itemID
        refreshStats()
    }

    // MARK: - 取线出口
    /// 设置/清空某个取线出口当前取货的材料（itemId）
    func setOutletMaterial(_ itemID: String?, for buildingID: UUID) {
        guard let idx = layout.buildings.firstIndex(where: { $0.id == buildingID }) else { return }
        layout.buildings[idx].outletMaterialID = itemID
        refreshStats()
    }

    // MARK: - 网格点击处理
    /// 点击：slop 是格子缩得很小时额外放宽的命中范围（格数），保证手指至少有 ~44pt 的可点区域
    func handleTap(at cell: GridPoint, slop: Int = 0) {
        // 正在摆布局：点哪里虚影就挪到哪里（以点的格子为中心）
        if let placement = pendingPlacement {
            movePlacement(to: GridPoint(col: cell.col - placement.size.width / 2, row: cell.row - placement.size.height / 2))
            return
        }
        if let id = movingBuildingID {
            if canReposition(id, to: cell) {
                commitReposition(id, to: cell)
                movingBuildingID = nil
                moveFailedMessage = nil
            } else {
                moveFailedMessage = "这里放不下，换个位置（点的格子是建筑新的左上角）"
            }
            return
        }
        switch editMode {
        case .erase:
            eraseAt(cell: cell)
        case .place(let def):
            // 点到已有的建筑/线就选中它，点空地才放建筑
            if !select(at: cell, slop: 0) { placeBuilding(def, at: cell) }
        case .select, .belt, .pipe:
            // 画线模式下轻点（不拖）也算选中
            if !select(at: cell, slop: slop) { clearSelection() }
        case .boxSelect:
            toggleGroupMember(at: cell, slop: slop)
        }
    }

    func clearSelection() {
        selectedBuildingID = nil
        clearBeltSelection()
    }

    func clearBeltSelection() {
        selectedBeltID = nil
        selectedBeltCell = nil
    }

    /// 先找建筑，再找线；同一格有好几条线（十字交叉/传送带管道同格）时，连点会轮流选中下一条。
    /// 点的格子上什么都没有时，在 slop 格范围内找最近的
    @discardableResult
    func select(at cell: GridPoint, slop: Int) -> Bool {
        for radius in 0...max(0, slop) {
            let cells = radius == 0 ? [cell] : ring(around: cell, radius: radius)
            for c in cells {
                if let hit = building(at: c) {
                    selectedBuildingID = hit.placed.id
                    return true
                }
            }
            for c in cells {
                let ids = layout.beltNetwork.beltIDs(at: c)
                guard !ids.isEmpty else { continue }
                let next: UUID
                if let current = selectedBeltID, let idx = ids.firstIndex(of: current), selectedBeltCell == c {
                    next = ids[(idx + 1) % ids.count]
                } else {
                    next = ids[0]
                }
                selectedBeltID = next
                selectedBeltCell = c
                return true
            }
        }
        return false
    }

    func ring(around cell: GridPoint, radius r: Int) -> [GridPoint] {
        var out: [GridPoint] = []
        for dr in -r...r {
            for dc in -r...r where max(abs(dr), abs(dc)) == r {
                out.append(GridPoint(col: cell.col + dc, row: cell.row + dr))
            }
        }
        return out.sorted { abs($0.col - cell.col) + abs($0.row - cell.row) < abs($1.col - cell.col) + abs($1.row - cell.row) }
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

    // MARK: - 开关 / 移动
    /// 关掉的建筑不参与模拟、不耗电，网格上半透明显示
    func toggleActive(_ id: UUID) {
        guard let idx = layout.buildings.firstIndex(where: { $0.id == id }) else { return }
        layout.buildings[idx].isActive.toggle()
        refreshStats()
    }

    func startMoving(_ id: UUID) {
        movingBuildingID = id
        moveFailedMessage = nil
    }

    func cancelMoving() {
        movingBuildingID = nil
        moveFailedMessage = nil
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
        let old = layout.buildings[idx]
        layout.buildings[idx].rotation = layout.buildings[idx].rotation.next
        if let def = BuildingDefinition.find(old.definitionID) {
            reattachLines(old: old, new: layout.buildings[idx], def: def)
        }
        refreshStats()
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

        let finalAxis: BeltAxis = (finalDir == .up || finalDir == .down) ? .vertical : .horizontal
        var segs: [BeltSegment] = []
        if start != snap.externalCell {
            // buildBeltSegments 只走到终点的前一格（最后一段指向终点），所以"口前一格"要自己补上，
            // 在这格拐进 finalDir；以前漏了这格，最后一段方向跟 finalDir 不一致时会直接斜着连到口外那格
            if start != approachCell {
                segs = buildBeltSegments(from: start, to: approachCell, currentPoint: currentPoint, lineType: lineType)
            }
            let inDir = segs.last?.toDir ?? finalDir.outputOffset
            segs.append(BeltSegment(cell: approachCell, axis: finalAxis,
                                    fromDir: inDir, toDir: finalDir.outputOffset, lineType: lineType))
        }
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
        // 中间有段因为跟已有的线重叠被去掉了：剩下的断成几截，各自按一条线处理，不然断口两头会被直接连起来画成斜线
        let pieces = splitIntoSubBelts(filtered)
        if pieces.count > 1 {
            for piece in pieces { commitSegments(piece.segments) }
            return
        }

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

    func autoPlaceBridgeIfCrossing(at cell: GridPoint, lineType: LineType) {
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

    // MARK: - 删除
    /// 协议核心不让删，点了给个提示
    @Published var eraseBlockedMessage: String? = nil

    /// 删除工具：建筑直接收纳、线直接删这一格，不弹确认（可以撤销）。按住划过去时每进一格调一次
    func eraseAt(cell: GridPoint) {
        if let hit = building(at: cell) {
            if hit.def.isProtocolCore {
                eraseBlockedMessage = "协议核心是地图必需的核心仓库，不能删除"
                return
            }
            removeBuilding(hit.placed, def: hit.def)
            return
        }
        guard !layout.beltNetwork.beltIDs(at: cell).isEmpty else { return }
        removeCellFromAllBelts(cell, lineType: nil)
        refreshStats()
    }

    func removeBuilding(_ placed: PlacedBuilding, def: BuildingDefinition) {
        let cells = placed.occupiedCells(definition: def)
        layout.buildings.removeAll { $0.id == placed.id }
        for cell in cells { removeCellFromAllBelts(cell, lineType: nil) }
        if selectedBuildingID == placed.id { selectedBuildingID = nil }
        if movingBuildingID == placed.id { cancelMoving() }
        groupSelection.remove(placed.id)
        refreshStats()
    }

    // MARK: - 选中的线：删整条 / 删这一格（整条要确认，在界面上弹）
    var selectedBelt: Belt? {
        layout.beltNetwork.belts.first { $0.id == selectedBeltID }
    }

    func deleteSelectedBelt() {
        guard let id = selectedBeltID else { return }
        layout.beltNetwork.belts.removeAll { $0.id == id }
        clearBeltSelection()
        refreshStats()
    }

    func deleteSelectedBeltCell() {
        guard let belt = selectedBelt, let cell = selectedBeltCell else { return }
        let remaining = belt.segments.filter { $0.cell != cell }
        let pieces = splitIntoSubBelts(remaining)
        layout.beltNetwork.belts.removeAll { $0.id == belt.id }
        layout.beltNetwork.belts.append(contentsOf: pieces)
        clearBeltSelection()
        refreshStats()
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
            // 没删到这条就原样保留（ID 不变，选中状态才跟得住）
            if remaining.count == belt.segments.count {
                newBelts.append(belt)
                continue
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
        guard let placed = selectedPlaced, let def = selectedDefinition else { return }
        guard !def.isProtocolCore else {
            eraseBlockedMessage = "协议核心是地图必需的核心仓库，不能删除"
            return
        }
        removeBuilding(placed, def: def)
    }

    // MARK: - 保存/清空
    func saveLayout() {
        var toSave = layout
        toSave.savedAt = .now
        FactoryGridModel.save(toSave)
        toastText = "画布已保存"
        showSaveConfirm = true
    }

    func clearLayout() {
        layout = .empty
        FactoryGridModel.ensureProtocolCore(in: &layout)
        selectedBuildingID = nil
        beltStart = nil
        beltPreviewSegments = []
        clearSelection()
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

    // MARK: - 拖拽重定位已放置建筑
    /// 校验某台已放置建筑挪到新坐标合不合法（碰撞检测要把它自己从"已有建筑"里排除，不然永远撞自己）
    func canReposition(_ id: UUID, to origin: GridPoint) -> Bool {
        guard let placed = layout.buildings.first(where: { $0.id == id }),
              let def = BuildingDefinition.find(placed.definitionID)
        else { return false }
        let others = layout.buildings.filter { $0.id != id }
        return FactoryGridModel.canPlace(definition: def, at: origin, rotation: placed.rotation,
                                         existing: others, mapType: layout.mapType)
    }

    /// 提交重定位；坐标不合法就什么都不做（原地不动）。注意：建筑身上原来接的传送带/管道
    /// 还是钉在旧坐标上，挪动后这些线不会跟着走，需要用户自己重新接
    func commitReposition(_ id: UUID, to origin: GridPoint) {
        guard canReposition(id, to: origin),
              let idx = layout.buildings.firstIndex(where: { $0.id == id })
        else { return }
        let old = layout.buildings[idx]
        layout.buildings[idx].origin = origin
        if let def = BuildingDefinition.find(old.definitionID) {
            reattachLines(old: old, new: layout.buildings[idx], def: def)
        }
        refreshStats()
    }

    // MARK: - 建筑挪动/旋转后，线跟着走
    /// 走不通被断开的线数量提示
    @Published var lineReattachMessage: String? = nil

    /// 原来线头/线尾落在这台建筑某个口外面那一格上的线，改接到口的新位置：
    /// 另一端不动，中间按 L 形重新走（两种拐法都试，避开建筑），都走不通就把这条线删掉并提示。
    /// excluding：整组移动时已经整条平移过的线，不再改接
    /// 返回断开的线数量
    @discardableResult
    func reattachLines(old: PlacedBuilding, new: PlacedBuilding, def: BuildingDefinition, excluding: Set<UUID> = []) -> Int {
        struct Attach { let beltID: UUID; let atHead: Bool; let port: BuildingPort }
        var attaches: [Attach] = []
        for port in def.ports {
            let (cell, facing) = port.resolvedPosition(placed: old, definition: def)
            let ext = cell + facing.outputOffset
            let kind: LineType = port.kind == .item ? .belt : .pipe
            for belt in layout.beltNetwork.belts where belt.lineType == kind && !excluding.contains(belt.id) {
                if port.ioDirection == .output, belt.headCell == ext {
                    attaches.append(Attach(beltID: belt.id, atHead: true, port: port))
                }
                if port.ioDirection == .input, belt.tailCell == ext {
                    attaches.append(Attach(beltID: belt.id, atHead: false, port: port))
                }
            }
        }
        guard !attaches.isEmpty else { return 0 }
        var broken = 0
        for (beltID, list) in Dictionary(grouping: attaches, by: \.beltID) {
            guard let idx = layout.beltNetwork.belts.firstIndex(where: { $0.id == beltID }),
                  var start = layout.beltNetwork.belts[idx].headCell,
                  var end = layout.beltNetwork.belts[idx].tailCell,
                  var finalDir = layout.beltNetwork.belts[idx].segments.last?.toDir
            else { continue }
            let lineType = layout.beltNetwork.belts[idx].lineType
            for a in list {
                let (cell, facing) = a.port.resolvedPosition(placed: new, definition: def)
                let ext = cell + facing.outputOffset
                if a.atHead {
                    start = ext
                } else {
                    end = ext
                    finalDir = facing.opposite.outputOffset
                }
            }
            if let segs = routeLine(from: start, to: end, finalDir: finalDir, lineType: lineType) {
                layout.beltNetwork.belts[idx].segments = segs
            } else {
                layout.beltNetwork.belts.remove(at: idx)
                broken += 1
            }
        }
        if broken > 0 {
            lineReattachMessage = "有 \(broken) 条线在新位置走不通，已经断开，需要重新接"
        }
        return broken
    }

    /// start → end 的 L 形线（end 那一格朝 finalDir），先横后竖、先竖后横都试，挑不压建筑的
    private func routeLine(from start: GridPoint, to end: GridPoint, finalDir: GridPoint, lineType: LineType) -> [BeltSegment]? {
        let axis: BeltAxis = finalDir.col == 0 ? .vertical : .horizontal
        let last = BeltSegment(cell: end, axis: axis, fromDir: finalDir, toDir: finalDir, lineType: lineType)
        if start == end { return [last] }
        let blocking = lineBlockingCellKeys()
        for hint in [CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1)] {
            let segs = buildBeltSegments(from: start, to: end, currentPoint: hint, lineType: lineType) + [last]
            if !segs.contains(where: { blocking.contains("\($0.cell.col),\($0.cell.row)") }) { return segs }
        }
        return nil
    }

    var selectedPlaced: PlacedBuilding? {
        layout.buildings.first { $0.id == selectedBuildingID }
    }

    var selectedDefinition: BuildingDefinition? {
        guard let p = selectedPlaced else { return nil }
        return BuildingDefinition.find(p.definitionID)
    }

    func refreshStats() {
        stats = FactoryGridModel.analyze(layout: layout, machineRecipes: machineRecipes)
    }
}
