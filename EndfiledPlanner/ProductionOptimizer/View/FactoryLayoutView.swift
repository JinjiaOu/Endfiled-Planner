//
//  FactoryLayoutView.swift
//  EndfiledPlanner
//
//  Created by Jinjia Ou on 4/3/26.
//

import SwiftUI
import UIKit
import Combine

/// 把 FactoryLayoutView 里一大串 .alert/.confirmationDialog 拆出来单独一个 ViewModifier——
/// 全堆在 body 那条链上会导致 Swift 类型检查超时编译不过
private struct FactoryAlertsModifier: ViewModifier {
    @ObservedObject var vm: FactoryViewModel
    @Binding var showClearConfirm: Bool
    @Binding var pendingPreset: FactoryPreset?
    @Binding var pendingMapSwitch: MapType?

    func body(content: Content) -> some View {
        content
            .alert("清空布局", isPresented: $showClearConfirm) {
                Button("取消", role: .cancel) {}
                Button("清空", role: .destructive) { vm.clearLayout() }
            } message: {
                Text("将删除所有建筑和传送带（可以撤销）。")
            }
            .alert(
                "加载预设产线",
                isPresented: Binding(
                    get: { pendingPreset != nil },
                    set: { if !$0 { pendingPreset = nil } }
                ),
                presenting: pendingPreset
            ) { preset in
                Button("取消", role: .cancel) { pendingPreset = nil }
                Button("加载", role: .destructive) {
                    vm.loadPreset(preset)
                    pendingPreset = nil
                }
            } message: { preset in
                Text(preset.summary)
            }
            // 切换地图确认
            .alert(
                pendingMapSwitch.map { "切换到\($0.displayName)？" } ?? "切换地图",
                isPresented: Binding(
                    get: { pendingMapSwitch != nil },
                    set: { if !$0 { pendingMapSwitch = nil } }
                )
            ) {
                Button("取消", role: .cancel) { pendingMapSwitch = nil }
                Button("切换", role: .destructive) {
                    if let map = pendingMapSwitch { vm.switchMap(to: map) }
                    pendingMapSwitch = nil
                }
            } message: {
                Text("两张地图的仓库取线规则不一样，切换会清空当前所有建筑和传送带（可以撤销）。")
            }
            // 挪动/旋转建筑后有线走不通被断开
            .alert(
                "线路已断开",
                isPresented: Binding(
                    get: { vm.lineReattachMessage != nil },
                    set: { if !$0 { vm.lineReattachMessage = nil } }
                )
            ) {
                Button("知道了", role: .cancel) { vm.lineReattachMessage = nil }
            } message: {
                Text(vm.lineReattachMessage ?? "")
            }
            // 协议核心不让删的提示
            .alert(
                "无法收纳",
                isPresented: Binding(
                    get: { vm.eraseBlockedMessage != nil },
                    set: { if !$0 { vm.eraseBlockedMessage = nil } }
                )
            ) {
                Button("知道了", role: .cancel) { vm.eraseBlockedMessage = nil }
            } message: {
                Text(vm.eraseBlockedMessage ?? "")
            }
    }
}

struct FactoryLayoutView: View {

    /// 作为平级编辑器使用时提供退出入口；原有 push / Preview 调用仍可不传。
    var onExit: (() -> Void)? = nil
    var entryID: UUID? = nil

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var vm: FactoryViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var showGuide = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var workspaceSize: CGSize = .zero

    // 网格缩放
    @State private var cellSize: CGFloat = 72
    @State private var lastCellSize: CGFloat = 72
    private let minCellSize: CGFloat = 16
    private let maxCellSize: CGFloat = 120

    // 建筑板
    @State private var showBuildingPalette = false
    @State private var selectedCategory: BuildingCategory? = nil

    // 拖拽放置状态
    @State private var draggingDef: BuildingDefinition? = nil
    @State private var dragLocationInGrid: CGPoint? = nil   // 相对于网格原点

    // 框选时拖到画面边缘自动滚动
    @State private var autoScrollFinger: CGPoint? = nil      // 手指全局坐标，没在框选拖动时为 nil
    @State private var scrollPosition = ScrollPosition()
    /// 滚动位置/画面框每滚一下都变，放在引用类型里改，避免每帧都触发整个画布重新计算
    @State private var scrollGeometry = ScrollGeometryBox()
    private let autoScrollTimer = Timer.publish(every: 1.0 / 60, on: .main, in: .common).autoconnect()

    // 悬浮 Stats
    @State private var showStats = false
    @State private var showUtilizationLegend = false

    // 其他
    @State private var showClearConfirm = false
    @State private var pendingMapSwitch: MapType? = nil
    @State private var pendingPreset: FactoryPreset? = nil

    // 我的布局
    @StateObject private var myLayouts = MyLayoutStore()
    @State private var showMyLayouts = false
    @State private var showSaveGroupPrompt = false
    @State private var saveGroupName = ""
    /// 列表里点了要放的布局：等列表关掉后再处理（跨地图要先弹提醒）
    @State private var layoutToPlace: SavedLayout? = nil
    @State private var crossMapLayout: SavedLayout? = nil
    @State private var crossMapWarnings: [String] = []

    init(onExit: (() -> Void)? = nil, entryID: UUID? = nil, viewModel: FactoryViewModel? = nil) {
        self.onExit = onExit
        self.entryID = entryID
        _vm = StateObject(wrappedValue: viewModel ?? FactoryViewModel())
    }

    private var usesSidePalette: Bool {
        horizontalSizeClass == .regular && workspaceSize.width >= (dynamicTypeSize.isAccessibilitySize ? 1000 : 760) && workspaceSize.height >= 520
    }

    private var bottomPanelHeight: CGFloat { max(120, workspaceSize.height * 0.42) }

    private var detailContentHeight: CGFloat {
        min(260, max(96, workspaceSize.height * 0.25))
    }

    var body: some View {
        ZStack {
            FactoryCanvasPalette.background.ignoresSafeArea()

            VStack(spacing: 0) {
                FactoryWorkspaceHeader(vm: vm, buildingPaletteVisible: showBuildingPalette)
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        canvasWorkspace
                        toolBar
                        if !usesSidePalette { bottomInspector }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if usesSidePalette {
                        sideInspector
                            .frame(width: dynamicTypeSize.isAccessibilitySize ? 360 : 304)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .background(AppColors.surface)
                            .clipped()
                            .overlay(alignment: .leading) {
                                Rectangle().fill(AppColors.border).frame(width: 1)
                                    .allowsHitTesting(false)
                            }
                    }
                }
            }

            // 产能统计 overlay
            if showStats {
                statsOverlay
            }

            // 保存提示
            if vm.showSaveConfirm { saveToast }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { workspaceSize = $0 }
        .navigationTitle("基建规划")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(onExit != nil)
        .toolbar {
            if let onExit {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onExit) {
                        Label("工作台", systemImage: "chevron.left")
                    }
                    .accessibilityLabel("返回工作台，保留当前编辑状态")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button { vm.saveLayout() } label: {
                        Label("保存画布", systemImage: "square.and.arrow.down")
                    }
                    Button { exportLayoutImage() } label: {
                        Label("导出布局图片", systemImage: "photo")
                    }
                    Button { showGuide = true } label: {
                        Label("使用指南", systemImage: "questionmark.circle")
                    }
                    Menu {
                        ForEach(MapType.allCases, id: \.self) { map in
                            Button {
                                if map != vm.layout.mapType { pendingMapSwitch = map }
                            } label: {
                                if map == vm.layout.mapType {
                                    Label(map.displayName, systemImage: "checkmark")
                                } else {
                                    Text(map.displayName)
                                }
                            }
                        }
                    } label: {
                        Label("切换地图（当前：\(vm.layout.mapType.displayName)）", systemImage: "map")
                    }
                    ForEach(FactoryPreset.allCases) { preset in
                        Button { pendingPreset = preset } label: {
                            Label(preset.menuTitle, systemImage: "wand.and.stars")
                        }
                    }
                    Button(role: .destructive) { showClearConfirm = true } label: {
                        Label("清空布局", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(AppColors.accent)
                }
                .accessibilityLabel("画布选项：保存、导出图片、使用指南、地图、预设与清空")
                // 挂在菜单上，不往主视图的修饰链里加（那条链再长会类型检查超时）
                .sheet(isPresented: $showGuide) {
                    NavigationStack { FactoryGuideView() }
                }
            }
        }
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(AppColors.background, for: .navigationBar)
        .tint(AppColors.accent)
        .alert("存为布局", isPresented: $showSaveGroupPrompt) {
            TextField("布局名字", text: $saveGroupName)
            Button("取消", role: .cancel) {}
            Button("保存") { saveGroup() }
        } message: {
            Text("选中的建筑和它们的设置、选中的线，以及两头接在这些建筑上的线会一起存下来")
        }
        .sheet(isPresented: $showMyLayouts, onDismiss: handleLayoutToPlace) {
            MyLayoutsView(store: myLayouts, currentMap: vm.layout.mapType) { layoutToPlace = $0 }
        }
        .alert("跨地图放置", isPresented: Binding(get: { crossMapLayout != nil }, set: { if !$0 { crossMapLayout = nil } })) {
            Button("取消", role: .cancel) { crossMapLayout = nil }
            Button("仍然放置") {
                if let saved = crossMapLayout { beginPlacement(saved) }
                crossMapLayout = nil
            }
        } message: {
            Text("这份布局来自\(crossMapLayout?.mapType.displayName ?? "")，放到\(vm.layout.mapType.displayName)后下面这些会标红、不参与计算：\n"
                 + crossMapWarnings.joined(separator: "\n"))
        }
        .modifier(FactoryAlertsModifier(vm: vm, showClearConfirm: $showClearConfirm,
                                       pendingPreset: $pendingPreset,
                                       pendingMapSwitch: $pendingMapSwitch))
        .modifier(OptimizerDisclaimerModifier(entryID: entryID))
    }

    // MARK: - 自适应工作区
    // 侧栏参与布局，画布的可滚动范围与拖拽坐标来自真实剩余区域。
    private var canvasWorkspace: some View {
        GeometryReader { _ in
            ZStack {
                // 可滚动的网格
                ScrollView([.horizontal, .vertical], showsIndicators: false) {
                    FactoryGridView(
                        vm: vm,
                        cellSize: cellSize,
                        draggingDef: $draggingDef,
                        dragLocationInGrid: $dragLocationInGrid,
                        autoScrollFinger: $autoScrollFinger
                    )
                    .padding(20)
                    .padding(.top, warehouseMargin.top)
                    .padding(.leading, warehouseMargin.leading)
                }
                .scrollPosition($scrollPosition)
                .onScrollGeometryChange(for: ScrollMetrics.self) { geo in
                    ScrollMetrics(offset: geo.contentOffset, contentSize: geo.contentSize,
                                  containerSize: geo.containerSize)
                } action: { _, metrics in
                    scrollGeometry.metrics = metrics
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { scrollGeometry.viewport = $0 }
                .onReceive(autoScrollTimer) { _ in autoScrollStep() }
                // simultaneousGesture 让双指缩放和 belt DragGesture 共存
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { v in
                            cellSize = min(max(lastCellSize * v, minCellSize), maxCellSize)
                        }
                        .onEnded { _ in lastCellSize = cellSize }
                )
                // 电力提示（画布顶部）：发电不够、或者有建筑不在供电桩范围内时才出现
                VStack {
                    powerWarningBanner
                        .padding(.top, 8)
                        .padding(.horizontal, 16)
                        .allowsHitTesting(false)
                    if let item = vm.highlightedItem {
                        highlightChip(item)
                            .padding(.top, AppSpacing.xs)
                    }
                    Spacer()
                }
                // 悬浮产能按钮（右下角）
                VStack {
                    Spacer()
                    HStack(alignment: .bottom, spacing: 10) {
                        Spacer()
                        canvasControls
                            .padding(.trailing, AppSpacing.md)
                    }
                    .padding(.bottom, 16)
                }
            }
        }
    }

    private var bottomInspector: some View {
        VStack(spacing: 0) {
            if vm.pendingPlacement != nil {
                PlacementPanel(vm: vm, maxPanelHeight: bottomPanelHeight)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if showBuildingPalette {
                buildingPalette(vertical: false)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if vm.editMode == .boxSelect {
                GroupSelectionPanel(vm: vm, style: .bottom, maxPanelHeight: bottomPanelHeight, onSaveAs: promptSaveGroup)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let placed = vm.selectedPlaced, let def = vm.selectedDefinition {
                BuildingDetailPanel(vm: vm, placed: placed, def: def, style: .bottom, maxContentHeight: detailContentHeight, maxPanelHeight: bottomPanelHeight)
                    .id(placed.id)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let belt = vm.selectedBelt {
                BeltDetailPanel(vm: vm, belt: belt, style: .bottom, maxContentHeight: detailContentHeight, maxPanelHeight: bottomPanelHeight)
                    .id(belt.id)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(AppMotion.panel(reduceMotion: reduceMotion), value: showBuildingPalette)
        .animation(AppMotion.panel(reduceMotion: reduceMotion), value: vm.selectedBuildingID)
        .animation(AppMotion.panel(reduceMotion: reduceMotion), value: vm.selectedBeltID)
        .animation(AppMotion.panel(reduceMotion: reduceMotion), value: vm.editMode == .boxSelect)
        .animation(AppMotion.panel(reduceMotion: reduceMotion), value: vm.pendingPlacement != nil)
    }

    @ViewBuilder
    private var sideInspector: some View {
        if vm.pendingPlacement != nil {
            PlacementPanel(vm: vm, style: .side)
        } else if showBuildingPalette {
            buildingPalette(vertical: true)
        } else if vm.editMode == .boxSelect {
            GroupSelectionPanel(vm: vm, style: .side, onSaveAs: promptSaveGroup)
        } else if let placed = vm.selectedPlaced, let def = vm.selectedDefinition {
            BuildingDetailPanel(vm: vm, placed: placed, def: def, style: .side)
                .id(placed.id)
        } else if let belt = vm.selectedBelt {
            BeltDetailPanel(vm: vm, belt: belt, style: .side)
                .id(belt.id)
        } else {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                AppSectionHeader(title: "属性检查器", subtitle: "选择建筑或线路")
                Text("点按画布中的设施查看配置与运行状态，也可以从建造面板添加设施。")
                    .font(AppTypography.supporting)
                    .foregroundStyle(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    showBuildingPalette = true
                    vm.editMode = .select
                } label: {
                    Label("建造设施", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(AppActionStyle(emphasis: .secondary))
                Spacer(minLength: 0)
            }
            .padding(AppSpacing.md)
        }
    }

    // MARK: - 工具栏
    private var toolBar: some View {
        FactoryWorkspaceToolbar(vm: vm, showBuildingPalette: $showBuildingPalette, showMyLayouts: $showMyLayouts,
                                horizontalLabels: usesSidePalette && workspaceSize.width >= 1000)
    }

    // MARK: - 建筑选择板（拖拽放置）
    /// vertical：iPad 右侧面板用竖向网格（分类横向滚动、建筑按可用宽度自适应列数上下滑）；手机底部用横向一排
    @ViewBuilder
    private func buildingPalette(vertical: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: AppSpacing.xs) {
                Text("设施").font(AppTypography.rowTitle)
                Text("长按拖入画布").font(AppTypography.caption).foregroundStyle(AppColors.secondaryText)
                Spacer(minLength: 0)
                placementRotationButton
                AppIconButton(title: "关闭建造面板", systemImage: "xmark") {
                    withAnimation(AppMotion.panel(reduceMotion: reduceMotion)) {
                        showBuildingPalette = false
                        vm.editMode = .select
                    }
                }
            }
            .foregroundStyle(AppColors.primaryText)
            .padding(.leading, AppSpacing.md)
            .padding(.trailing, AppSpacing.xxs)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.xxs) {
                    categoryChip(category: nil, label: "全部")
                    ForEach(BuildingCategory.allCases, id: \.self) { cat in
                        categoryChip(category: cat, label: cat.rawValue)
                    }
                }
                .padding(.horizontal, AppSpacing.xs)
            }
            .fixedSize(horizontal: false, vertical: true)

            if vertical {
                ScrollView(.vertical) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: AppSpacing.xs)], spacing: AppSpacing.xs) {
                        ForEach(filteredBuildings) { def in draggableBuildingChip(def) }
                    }
                    .padding(AppSpacing.xs)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: AppSpacing.xs) {
                        ForEach(filteredBuildings) { def in draggableBuildingChip(def) }
                    }
                    .padding(.horizontal, AppSpacing.xs)
                    .padding(.vertical, AppSpacing.xs)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .background(AppColors.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(AppColors.border).frame(height: 1).allowsHitTesting(false)
        }
    }

    private var placementRotationButton: some View {
        Button { vm.pendingRotation = vm.pendingRotation.next } label: {
            Label(vm.pendingRotation.symbol, systemImage: "rotate.right")
                .font(AppTypography.supporting)
                .foregroundStyle(AppColors.secondaryText)
                .padding(.horizontal, AppSpacing.xs)
                .frame(minWidth: AppSize.touchTarget, minHeight: AppSize.touchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("放置前旋转，当前朝向 \(vm.pendingRotation.symbol)")
    }

    private var filteredBuildings: [BuildingDefinition] {
        // 协议核心每张图自动生成、全局唯一，不放进建造面板里让人手动摆第二个
        let onMap = BuildingDefinition.all.filter { $0.isAvailable(on: vm.layout.mapType) && !$0.isProtocolCore }
        guard let cat = selectedCategory else { return onMap }
        return onMap.filter { $0.category == cat }
    }

    private func categoryChip(category: BuildingCategory?, label: String) -> some View {
        let selected = category == selectedCategory
        return Button { selectedCategory = category } label: {
            Text(label)
                .font(AppTypography.caption.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? AppColors.accent : AppColors.secondaryText)
                .padding(.horizontal, AppSpacing.xs)
                .frame(minWidth: AppSize.touchTarget, minHeight: AppSize.touchTarget)
                .contentShape(Rectangle())
                .overlay(alignment: .bottom) {
                    if selected { Capsule().fill(AppColors.accent).frame(height: 2).padding(.horizontal, AppSpacing.xs) }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// 建筑卡片：按住再拖时激活拖拽状态，松手时在网格对应位置放置
    private func draggableBuildingChip(_ def: BuildingDefinition) -> some View {
        VStack(spacing: AppSpacing.xxs) {
            Image(systemName: def.category.icon)
                .font(.title3.weight(.medium))
                .foregroundStyle(def.category.color)
                .frame(height: 28)
            Text(def.name).font(AppTypography.caption.weight(.medium))
                .foregroundStyle(AppColors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(def.size.width)×\(def.size.height)")
                .font(.caption2.monospacedDigit()).foregroundStyle(AppColors.tertiaryText)
        }
        .multilineTextAlignment(.center)
        .padding(.vertical, AppSpacing.xxs)
        .frame(width: dynamicTypeSize.isAccessibilitySize ? 144 : 88)
        .scaleEffect(!reduceMotion && draggingDef?.id == def.id ? 1.04 : 1.0)
        .animation(AppMotion.feedback(reduceMotion: reduceMotion), value: draggingDef?.id)
        // 先按住 0.2 秒再拖才算"拿建筑去放置"，手指一按下就滑动则交给外面的 ScrollView 滚动。
        // SwiftUI 自己的 DragGesture / 长按+拖（不管 gesture 还是 simultaneousGesture）在新版 iOS 上
        // 都会把卡片区域的列表滑动吃掉，所以改用 UIKit 的长按手势：它和 ScrollView 的滑动是同一套
        // 手势系统，按下就滑时长按自动失败，滚动不受影响；长按成功后手指移动会持续回调位置。
        // 原来长按弹出的"旋转"菜单会跟这个冲突，去掉了，放置前旋转用工具栏的旋转按钮
        .accessibilityElement(children: .combine)
        .accessibilityHint("长按并拖到画布放置")
        .gesture(PaletteHoldDragGesture(
            onChanged: { location in
                if draggingDef == nil {
                    draggingDef = def
                    vm.editMode = .place(def)
                }
                // 全局坐标，由 FactoryGridView 的 GeometryReader 换算成网格内坐标
                dragLocationInGrid = location
            },
            onEnded: { placed in
                if placed, draggingDef != nil, let cell = vm.pendingDropCell {
                    vm.placeBuilding(def, at: cell)
                }
                draggingDef = nil
                dragLocationInGrid = nil
                vm.pendingDropCell = nil
            }
        ))
    }

    // MARK: - 存为我的布局
    private func promptSaveGroup() {
        saveGroupName = myLayouts.suggestedName()
        showSaveGroupPrompt = true
    }

    private func saveGroup() {
        guard let saved = vm.makeSavedLayout(name: saveGroupName) else { return }
        myLayouts.add(saved)
        vm.toastText = "已存到我的布局：\(saved.name)"
        withAnimation { vm.showSaveConfirm = true }
    }

    // MARK: - 放置我的布局
    private func handleLayoutToPlace() {
        guard let saved = layoutToPlace else { return }
        layoutToPlace = nil
        let warnings = vm.placementWarnings(for: saved)
        if warnings.isEmpty {
            beginPlacement(saved)
        } else {
            crossMapWarnings = warnings
            crossMapLayout = saved
        }
    }

    /// 四号谷地外围画的仓库存取线示意要留出的位置（FactoryGridView.warehouseLineDecoration）
    private var warehouseMargin: (top: CGFloat, leading: CGFloat) {
        guard case .perimeter(let edges) = vm.layout.mapType.rules.warehouseLine else { return (0, 0) }
        let depth = CGFloat(FactoryGridView.warehouseLineDepth) * cellSize
        return (edges.contains(.up) ? depth : 0, edges.contains(.left) ? depth : 0)
    }

    /// 虚影放在当前画面中央
    private func beginPlacement(_ saved: SavedLayout) {
        let m = scrollGeometry.metrics
        let padding: CGFloat = 20   // 网格外面那圈 .padding(20)
        let center = GridPoint(col: Int((m.offset.x + m.containerSize.width / 2 - padding - warehouseMargin.leading) / cellSize),
                               row: Int((m.offset.y + m.containerSize.height / 2 - padding - warehouseMargin.top) / cellSize))
        showBuildingPalette = false
        vm.startPlacement(saved, around: center)
    }

    // MARK: - 框选拖到边缘自动滚动
    /// 手指离画面边缘不到 edge 点时，按离边缘多近往那边滚（越靠边越快），滚到内容尽头就停
    private func autoScrollStep() {
        let viewportFrame = scrollGeometry.viewport
        guard let finger = autoScrollFinger, viewportFrame.width > 0 else { return }
        let edge: CGFloat = 56
        let maxSpeed: CGFloat = 18
        func speed(_ distanceToEdge: CGFloat) -> CGFloat {
            distanceToEdge >= edge ? 0 : maxSpeed * (1 - max(0, distanceToEdge) / edge)
        }
        let dx = speed(finger.x - viewportFrame.minX) * -1 + speed(viewportFrame.maxX - finger.x)
        let dy = speed(finger.y - viewportFrame.minY) * -1 + speed(viewportFrame.maxY - finger.y)
        guard dx != 0 || dy != 0 else { return }
        let m = scrollGeometry.metrics
        let maxX = max(0, m.contentSize.width - m.containerSize.width)
        let maxY = max(0, m.contentSize.height - m.containerSize.height)
        let target = CGPoint(x: min(max(m.offset.x + dx, 0), maxX), y: min(max(m.offset.y + dy, 0), maxY))
        guard target != m.offset else { return }
        scrollPosition.scrollTo(point: target)
    }

    // MARK: - 电力提示
    /// 只是提示：模拟里电不够时机器照常按满速算，没有模拟缺电降速
    @ViewBuilder
    private var powerWarningBanner: some View {
        let stats = vm.stats
        let shortage = stats.powerShortage
        let unpowered = stats.unpoweredCount
        if shortage > 0.5 || unpowered > 0 {
            let red = Color(red: 0.95, green: 0.3, blue: 0.25)
            VStack(alignment: .leading, spacing: 3) {
                if shortage > 0.5 {
                    Label(String(format: "电力不足：缺 %.0f MW（耗电 %.0f / 发电 %.0f）",
                                 shortage, stats.totalPowerConsumed, stats.totalPowerGenerated),
                          systemImage: "bolt.trianglebadge.exclamationmark.fill")
                }
                if unpowered > 0 {
                    Label("\(unpowered) 个建筑不在供电桩范围内，不运行", systemImage: "bolt.slash.fill")
                }
            }
            .font(AppTypography.supporting)
            .foregroundColor(red)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(AppColors.elevatedSurface.opacity(0.92))
            .overlay(Rectangle().stroke(red.opacity(0.6), lineWidth: 1))
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - 利用率与统计
    private var canvasControls: some View {
        HStack(spacing: 0) {
            utilizationButton
            if vm.showUtilization {
                AppIconButton(title: "查看利用率图例", systemImage: "info.circle") { showUtilizationLegend = true }
                    .popover(isPresented: $showUtilizationLegend, arrowEdge: .bottom) {
                        utilizationLegend
                            .padding(AppSpacing.xs)
                            .presentationCompactAdaptation(.popover)
                    }
            }
            Rectangle().fill(AppColors.border).frame(width: 1, height: 18).accessibilityHidden(true)
            statsFloatingButton
        }
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: AppRadius.control))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.control)
                .stroke(vm.showUtilization ? AppColors.accent.opacity(0.65) : AppColors.controlBorder, lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    private var utilizationButton: some View {
        Button {
            withAnimation(AppMotion.feedback(reduceMotion: reduceMotion)) { vm.showUtilization.toggle() }
        } label: {
            Label("线的利用率", systemImage: "gauge.with.dots.needle.50percent")
                .font(AppTypography.caption.weight(.medium))
                .foregroundStyle(vm.showUtilization ? AppColors.accent : AppColors.secondaryText)
                .padding(.horizontal, AppSpacing.sm)
                .frame(minHeight: AppSize.touchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(vm.showUtilization ? "关闭利用率视图" : "打开利用率视图")
        .accessibilityAddTraits(vm.showUtilization ? .isSelected : [])
    }

    private var utilizationLegend: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("线的利用率").font(AppTypography.supporting.weight(.semibold))
                legendRow(swatch: AnyView(Rectangle().fill(FactoryGridView.utilizationFullColor)), text: "跑满")
                legendRow(swatch: AnyView(Text("60%").font(AppTypography.caption).foregroundStyle(.white)
                    .background(.black)), text: "没跑满（刻度与百分比）")
                legendRow(swatch: AnyView(Rectangle().fill(FactoryCanvasPalette.belt.opacity(0.25))),
                          text: "空闲（变暗）")
                legendRow(swatch: AnyView(Rectangle().fill(FactoryGridView.utilizationOverColor)), text: "被限流（瓶颈）")
            }
            .foregroundStyle(AppColors.primaryText)
        }
        .padding(AppSpacing.sm)
        .frame(maxWidth: 240)
        .transition(.opacity)
    }

    private func legendRow(swatch: AnyView, text: String) -> some View {
        HStack(spacing: AppSpacing.xs) {
            swatch.frame(width: 28, height: 12).accessibilityHidden(true)
            Text(text).font(AppTypography.caption).foregroundStyle(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 整张画布裁到有内容的区域导出成图片，弹分享面板；导出前先取消选中，免得选中框也画进去
    private func exportLayoutImage() {
        vm.selectedBuildingID = nil
        vm.selectedBeltID = nil
        guard let image = FactoryLayoutExporter.image(vm: vm, colorScheme: colorScheme) else {
            vm.toastText = "画布是空的，没有可导出的内容"
            vm.showSaveConfirm = true
            return
        }
        FactoryLayoutExporter.share(image)
    }

    /// 画布顶部的高亮提示：当前高亮哪个产物，点 × 取消
    private func highlightChip(_ item: String) -> some View {
        HStack(spacing: AppSpacing.xs) {
            ItemIcon(name: item, size: 20)
            Text("高亮：\(item)")
                .font(AppTypography.caption.weight(.semibold))
                .foregroundStyle(AppColors.primaryText)
                .lineLimit(1)
            Button {
                withAnimation(AppMotion.feedback(reduceMotion: reduceMotion)) { vm.highlightedItem = nil }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(AppColors.secondaryText)
                    .frame(minWidth: AppSize.touchTarget, minHeight: AppSize.touchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("取消高亮")
        }
        .padding(.leading, AppSpacing.sm)
        .background(AppColors.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(AppColors.accent, lineWidth: 1).allowsHitTesting(false))
    }

    private var statsFloatingButton: some View {
        Button {
            withAnimation(AppMotion.feedback(reduceMotion: reduceMotion)) { showStats.toggle() }
        } label: {
            Label("统计 · \(vm.stats.buildingCount)", systemImage: "chart.bar")
                .font(AppTypography.caption.weight(.medium))
                .foregroundStyle(AppColors.secondaryText)
                .padding(.horizontal, AppSpacing.sm)
                .frame(minHeight: AppSize.touchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("产能统计，\(vm.stats.buildingCount) 个建筑")
    }

    private var statsOverlay: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomTrailing) {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(AppMotion.feedback(reduceMotion: reduceMotion)) { showStats = false }
                    }
                    .accessibilityHidden(true)
                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: AppSpacing.xs) {
                        AppSectionHeader(title: "产能统计", subtitle: "当前布局的稳定产能估算")
                        AppIconButton(title: "关闭产能统计", systemImage: "xmark") { showStats = false }
                    }
                    .padding(AppSpacing.md)
                    Divider().overlay(AppColors.border)
                    ScrollView {
                        FactoryStatsView(stats: vm.stats, isExpanded: .constant(true), showsHeader: false,
                                         highlightedItem: vm.highlightedItem) { item in
                            // 点产物：画布上高亮相关机器和线，关掉统计面板让出画布
                            withAnimation(AppMotion.feedback(reduceMotion: reduceMotion)) {
                                vm.highlightedItem = vm.highlightedItem == item ? nil : item
                                showStats = false
                            }
                        }
                    }
                }
                .background(AppColors.surface, in: RoundedRectangle(cornerRadius: AppRadius.panel))
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.panel))
                .overlay {
                    RoundedRectangle(cornerRadius: AppRadius.panel).strokeBorder(AppColors.border, lineWidth: 1)
                        .allowsHitTesting(false)
                }
                .frame(width: max(0, min(520, geometry.size.width - AppSpacing.md * 2)),
                       height: max(0, min(720, geometry.size.height - AppSpacing.md * 2)))
                .padding(AppSpacing.md)
                .accessibilityElement(children: .contain)
                .accessibilityAction(.escape) { showStats = false }
            }
        }
        .transition(.opacity)
    }

    private var saveToast: some View {
        VStack {
            Spacer()
            AppFeedbackToast(title: vm.toastText)
                .padding(AppSpacing.md)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation(AppMotion.feedback(reduceMotion: reduceMotion)) { vm.showSaveConfirm = false }
                    }
                }
        }
        .transition(.opacity)
        .allowsHitTesting(false)
    }

}

#Preview {
    NavigationStack { FactoryLayoutView() }
}

/// 建筑卡片的"按住再拖"：UIKit 长按手势，按住 0.2 秒内手指没怎么动才开始，之后跟着手指回调全局坐标
private struct PaletteHoldDragGesture: UIGestureRecognizerRepresentable {
    var onChanged: (CGPoint) -> Void
    /// 参数：true = 正常松手（放置），false = 被系统取消（不放置）
    var onEnded: (Bool) -> Void

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = 0.2
        recognizer.allowableMovement = 10
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began, .changed:
            onChanged(context.converter.location(in: .global))
        case .ended:
            onEnded(true)
        case .cancelled, .failed:
            onEnded(false)
        default:
            break
        }
    }
}

private final class ScrollGeometryBox {
    var metrics = ScrollMetrics()
    var viewport: CGRect = .zero
}

/// 画布滚动位置和尺寸（自动滚动时算能滚多远）
private struct ScrollMetrics: Equatable {
    var offset: CGPoint = .zero
    var contentSize: CGSize = .zero
    var containerSize: CGSize = .zero
}
