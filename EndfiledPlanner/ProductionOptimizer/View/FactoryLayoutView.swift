//
//  FactoryLayoutView.swift
//  EndfiledPlanner
//
//  Created by Jinjia Ou on 4/3/26.
//

import SwiftUI

struct FactoryLayoutView: View {

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var vm = FactoryViewModel()

    // 网格缩放
    @State private var cellSize: CGFloat = 72
    @State private var lastCellSize: CGFloat = 72
    private let minCellSize: CGFloat = 40
    private let maxCellSize: CGFloat = 120

    // 建筑板
    @State private var showBuildingPalette = false
    @State private var selectedCategory: BuildingCategory? = nil

    // 拖拽放置状态
    @State private var draggingDef: BuildingDefinition? = nil
    @State private var dragLocationInGrid: CGPoint? = nil   // 相对于网格原点

    // 悬浮 Stats
    @State private var showStats = false

    // 其他
    @State private var showClearConfirm = false
    @State private var pendingMapSwitch: MapType? = nil

    private var usesSidePalette: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.06, green: 0.07, blue: 0.10).ignoresSafeArea()

                VStack(spacing: 0) {
                    toolBar

                    // 画布 + 拖拽放置覆盖
                    GeometryReader { geo in
                        ZStack {
                            // 可滚动的网格
                            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                                FactoryGridView(
                                    vm: vm,
                                    cellSize: cellSize,
                                    draggingDef: $draggingDef,
                                    dragLocationInGrid: $dragLocationInGrid
                                )
                                .padding(20)
                            }
                            // simultaneousGesture 让双指缩放和 belt DragGesture 共存
                            .simultaneousGesture(
                                MagnificationGesture()
                                    .onChanged { v in
                                        cellSize = min(max(lastCellSize * v, minCellSize), maxCellSize)
                                    }
                                    .onEnded { _ in lastCellSize = cellSize }
                            )

                            // 悬浮产能按钮（右下角）
                            VStack {
                                Spacer()
                                HStack {
                                    Spacer()
                                    statsFloatingButton
                                        .padding(.trailing, 16)
                                        .padding(.bottom, 16)
                                }
                            }
                        }
                    }

                    // 底部面板（建筑板 / 选中信息）
                    VStack(spacing: 0) {
                        if showBuildingPalette && !usesSidePalette {
                            buildingPalette
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        } else if let def = vm.selectedDefinition {
                            selectedBuildingInfo(def)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .animation(.spring(response: 0.3), value: showBuildingPalette)
                    .animation(.spring(response: 0.3), value: vm.selectedBuildingID)
                }

                if showBuildingPalette && usesSidePalette {
                    sideBuildingPalette
                }

                // 产能统计 overlay
                if showStats {
                    statsOverlay
                }

                // 保存提示
                if vm.showSaveConfirm { saveToast }
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Image(systemName: "building.2.fill")
                            .foregroundColor(Color(red: 1.0, green: 0.8, blue: 0.0))
                        Text("基建规划")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                        Text("· \(vm.layout.mapType.displayName)")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button { vm.saveLayout() } label: {
                            Label("保存布局", systemImage: "square.and.arrow.down")
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
                        Button(role: .destructive) { showClearConfirm = true } label: {
                            Label("清空布局", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(Color(red: 1.0, green: 0.8, blue: 0.0))
                    }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color(red: 0.08, green: 0.09, blue: 0.12), for: .navigationBar)
            .alert("清空布局", isPresented: $showClearConfirm) {
                Button("取消", role: .cancel) {}
                Button("清空", role: .destructive) { vm.clearLayout() }
            } message: {
                Text("将删除所有建筑和传送带，此操作不可撤销。")
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
                Text("两张地图的仓库取线规则不一样，切换会清空当前所有建筑和传送带，此操作不可撤销。")
            }
            // 删除建筑确认
            .alert(
                vm.pendingEraseBuilding.map { "删除 \($0.def.name)？" } ?? "删除建筑",
                isPresented: Binding(
                    get: { vm.pendingEraseBuilding != nil },
                    set: { if !$0 { vm.cancelErase() } }
                )
            ) {
                Button("取消", role: .cancel) { vm.cancelErase() }
                Button("删除", role: .destructive) { vm.confirmEraseBuilding() }
            } message: {
                Text("此操作不可撤销。")
            }
            // 删除传送带/管道确认（单格 or 整条；同格共存/十字交叉时可能同时命中传送带和管道，
            // 这种情况下拆开显示"只删传送带/只删管道/两者都删"，避免删一个把另一个也带走）
            .confirmationDialog(
                "删除线路",
                isPresented: Binding(
                    get: { vm.pendingEraseCell != nil },
                    set: { if !$0 { vm.cancelErase() } }
                ),
                titleVisibility: .visible
            ) {
                let types = vm.pendingEraseLineTypes
                if types.count > 1 {
                    ForEach(types, id: \.self) { type in
                        Button("只删\(type.displayName)（这一格）", role: .destructive) {
                            vm.confirmEraseCell(lineType: type)
                        }
                    }
                    Button("两者都删（这一格）", role: .destructive) { vm.confirmEraseCell() }
                    ForEach(types, id: \.self) { type in
                        Button("只删\(type.displayName)（整条）", role: .destructive) {
                            vm.confirmEraseWholeBelt(lineType: type)
                        }
                    }
                    Button("两者都删（整条）", role: .destructive) { vm.confirmEraseWholeBelt() }
                } else {
                    Button("删除这一格", role: .destructive) { vm.confirmEraseCell() }
                    Button("删除整条线路", role: .destructive) { vm.confirmEraseWholeBelt() }
                }
                Button("取消", role: .cancel) { vm.cancelErase() }
            } message: {
                Text("请选择删除范围")
            }
        }
    }

    private var sideBuildingPalette: some View {
        HStack {
            Spacer()

            VStack(spacing: 0) {
                HStack {
                    Rectangle()
                        .fill(Color(red: 0.4, green: 0.8, blue: 0.2))
                        .frame(width: 3, height: 16)

                    Text("建造面板")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.9))

                    Spacer()

                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            showBuildingPalette = false
                            vm.editMode = .select
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white.opacity(0.55))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(red: 0.08, green: 0.09, blue: 0.12))

                buildingPalette
            }
            .frame(width: 380)
            .background(Color(red: 0.10, green: 0.11, blue: 0.14))
            .overlay(
                Rectangle()
                    .stroke(Color(red: 0.4, green: 0.8, blue: 0.2).opacity(0.4), lineWidth: 1)
            )
            .padding(.trailing, 18)
            .padding(.top, 64)
            .padding(.bottom, 18)
        }
        .transition(.move(edge: .trailing).combined(with: .opacity))
        .zIndex(3)
    }

    // MARK: - 工具栏
    private var toolBar: some View {
        HStack(spacing: 0) {
            toolButton(icon: "cursorarrow", label: "选择",
                       isActive: vm.editMode == .select && !showBuildingPalette,
                       color: Color(red: 1.0, green: 0.8, blue: 0.0)) {
                vm.editMode = .select
                showBuildingPalette = false
            }
            Divider().overlay(Color.white.opacity(0.1))
            toolButton(icon: "plus.square.fill", label: "建造",
                       isActive: showBuildingPalette || { if case .place = vm.editMode { return true }; return false }(),
                       color: Color(red: 0.4, green: 0.8, blue: 0.2)) {
                withAnimation(.spring(response: 0.3)) {
                    showBuildingPalette.toggle()
                    if showBuildingPalette {
                        // 打开建筑板时切换到 place 模式的初始态（无具体建筑先用 select 占位）
                        // 实际 editMode 在用户点选建筑后才变成 .place(def)
                        vm.editMode = .select
                    } else {
                        vm.editMode = .select
                    }
                }
            }
            Divider().overlay(Color.white.opacity(0.1))
            toolButton(icon: "arrow.left.and.right", label: "传送带",
                       isActive: vm.editMode == .belt,
                       color: Color(red: 1.0, green: 0.55, blue: 0.1)) {
                vm.editMode = .belt
                showBuildingPalette = false
                vm.beltStart = nil
            }
            Divider().overlay(Color.white.opacity(0.1))
            toolButton(icon: "water.waves", label: "管道",
                       isActive: vm.editMode == .pipe,
                       color: Color(red: 0.3, green: 0.7, blue: 1.0)) {
                vm.editMode = .pipe
                showBuildingPalette = false
                vm.beltStart = nil
            }
            Divider().overlay(Color.white.opacity(0.1))
            toolButton(icon: "rotate.right", label: "旋转",
                       isActive: false,
                       color: Color(red: 0.7, green: 0.5, blue: 0.9)) {
                vm.rotateSelected()
            }
            Divider().overlay(Color.white.opacity(0.1))
            toolButton(icon: "trash.fill", label: "删除",
                       isActive: vm.editMode == .erase,
                       color: Color.red) {
                vm.editMode = .erase
                showBuildingPalette = false
            }
        }
        .frame(height: 52)
        .background(Color(red: 0.10, green: 0.11, blue: 0.14))
        .overlay(Rectangle()
            .stroke(Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.15), lineWidth: 1),
            alignment: .bottom)
    }

    private func toolButton(icon: String, label: String, isActive: Bool,
                            color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 16))
                    .foregroundColor(isActive ? color : .white.opacity(0.4))
                Text(label).font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(isActive ? color : .white.opacity(0.3))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 8)
            .background(isActive ? color.opacity(0.12) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 建筑选择板（拖拽放置）
    private var buildingPalette: some View {
        VStack(spacing: 0) {
            // 分类筛选
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    categoryChip(category: nil, label: "全部")
                    ForEach(BuildingCategory.allCases, id: \.self) { cat in
                        categoryChip(category: cat, label: cat.rawValue)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
            }
            .background(Color(red: 0.10, green: 0.11, blue: 0.14))

            // 建筑列表（每个卡片支持 DragGesture 拖入网格）
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(filteredBuildings) { def in
                        draggableBuildingChip(def)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
            }
            .background(Color(red: 0.12, green: 0.13, blue: 0.16))

            // 拖拽提示
            HStack(spacing: 6) {
                Image(systemName: "hand.draw.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.3))
                Text("拖拽建筑到网格放置 · 双指缩放")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(Color(red: 0.10, green: 0.11, blue: 0.14))
        }
        .overlay(Rectangle()
            .stroke(Color(red: 0.4, green: 0.8, blue: 0.2).opacity(0.3), lineWidth: 1),
            alignment: .top)
    }

    private var filteredBuildings: [BuildingDefinition] {
        let onMap = BuildingDefinition.all.filter { $0.isAvailable(on: vm.layout.mapType) }
        guard let cat = selectedCategory else { return onMap }
        return onMap.filter { $0.category == cat }
    }

    private func categoryChip(category: BuildingCategory?, label: String) -> some View {
        let isSelected = category == selectedCategory
        let color = category?.color ?? Color(red: 1.0, green: 0.8, blue: 0.0)
        return Button { selectedCategory = category } label: {
            Text(label)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(isSelected ? .black : color.opacity(0.8))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(isSelected ? color : color.opacity(0.1))
                .overlay(RoundedRectangle(cornerRadius: 0).stroke(color.opacity(0.4), lineWidth: 1))
        }.buttonStyle(.plain)
    }

    /// 建筑卡片：长按/拖拽开始时激活拖拽状态，松手时在网格对应位置放置
    private func draggableBuildingChip(_ def: BuildingDefinition) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Rectangle().fill(def.category.color.opacity(0.15)).frame(width: 52, height: 52)
                Rectangle().stroke(def.category.color.opacity(0.4), lineWidth: 1).frame(width: 52, height: 52)
                Image(systemName: def.category.icon).font(.system(size: 20))
                    .foregroundColor(def.category.color)
            }
            Text(def.name).font(.system(size: 10, weight: .bold))
                .foregroundColor(.white.opacity(0.7)).lineLimit(1)
            Text("\(def.size.width)×\(def.size.height)")
                .font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.4))
        }
        .frame(width: 72)
        .scaleEffect(draggingDef?.id == def.id ? 1.08 : 1.0)
        .animation(.spring(response: 0.2), value: draggingDef?.id)
        // 用 simultaneousGesture 而不是 gesture：普通的 .gesture 会独占这次触摸，
        // ScrollView 自己的横向滚动手势完全拿不到事件，怎么都滑不动。
        // simultaneousGesture 让两边都能收到触摸，这里再按“整体位移是不是明显偏纵向”
        // 来判断——明显往上拖才当成"拿建筑去放置"，左右滑动交给 ScrollView 正常滚动
        .simultaneousGesture(
            DragGesture(minimumDistance: 12, coordinateSpace: .global)
                .onChanged { value in
                    let isVerticalDrag = abs(value.translation.height) > abs(value.translation.width) * 1.2
                    guard isVerticalDrag || draggingDef != nil else { return }
                    if draggingDef == nil {
                        draggingDef = def
                        vm.editMode = .place(def)
                    }
                    // 将全局坐标转换为网格内坐标（近似：减去网格左上角偏移）
                    // 网格左上角约在屏幕 (0 + toolbar, 0)，用 global 坐标传过去
                    // FactoryGridView 通过 coordinateSpace 无法直接获取，这里用全局坐标暂存
                    // 由 FactoryGridView 的 GeometryReader 在父层做坐标转换
                    dragLocationInGrid = value.location
                }
                .onEnded { value in
                    if draggingDef != nil, let cell = vm.pendingDropCell {
                        vm.placeBuilding(def, at: cell)
                    }
                    draggingDef = nil
                    dragLocationInGrid = nil
                    vm.pendingDropCell = nil
                }
        )
        // 旋转按钮
        .contextMenu {
            Button { vm.pendingRotation = vm.pendingRotation.next } label: {
                Label("旋转", systemImage: "rotate.right")
            }
        }
    }

    // MARK: - 悬浮产能按钮
    private var statsFloatingButton: some View {
        Button {
            withAnimation(.spring(response: 0.35)) {
                showStats.toggle()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(Color(red: 0.10, green: 0.11, blue: 0.14))
                    .frame(width: 52, height: 52)
                Circle()
                    .stroke(Color(red: 0.4, green: 0.8, blue: 0.2).opacity(0.6), lineWidth: 1.5)
                    .frame(width: 52, height: 52)
                VStack(spacing: 1) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Color(red: 0.4, green: 0.8, blue: 0.2))
                    Text("\(vm.stats.buildingCount)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .shadow(color: Color(red: 0.4, green: 0.8, blue: 0.2).opacity(0.3), radius: 6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 产能统计 overlay（从角落弹出）
    private var statsOverlay: some View {
        ZStack(alignment: .bottomTrailing) {
            // 半透明背景蒙层，点击关闭
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.3)) { showStats = false }
                }

            // 统计卡片
            VStack(spacing: 0) {
                // 标题栏
                HStack {
                    Rectangle().fill(Color(red: 0.4, green: 0.8, blue: 0.2)).frame(width: 3, height: 14)
                    Text("产能统计")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.3)) { showStats = false }
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color(red: 0.08, green: 0.09, blue: 0.12))

                FactoryStatsView(stats: vm.stats, isExpanded: .constant(true))
            }
            .background(Color(red: 0.10, green: 0.11, blue: 0.14))
            .overlay(Rectangle().stroke(Color(red: 0.4, green: 0.8, blue: 0.2).opacity(0.4), lineWidth: 1))
            .frame(maxWidth: 340)
            .padding(.trailing, 16)
            .padding(.bottom, 80)   // 留出悬浮按钮空间
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .bottomTrailing)))
    }

    // MARK: - 选中建筑信息面板
    private func selectedBuildingInfo(_ def: BuildingDefinition) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Rectangle().fill(def.category.color.opacity(0.2)).frame(width: 44, height: 44)
                Rectangle().stroke(def.category.color.opacity(0.6), lineWidth: 1.5).frame(width: 44, height: 44)
                Image(systemName: def.category.icon).font(.system(size: 18))
                    .foregroundColor(def.category.color)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(def.name).font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                HStack(spacing: 10) {
                    if def.powerUsage > 0 {
                        Label(String(format: "%.1fMW", def.powerUsage), systemImage: "bolt.fill")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Color(red: 0.9, green: 0.5, blue: 0.2))
                    }
                }
                recipePicker(for: def)
                outletMaterialPicker(for: def)
            }
            Spacer()
            VStack(spacing: 6) {
                Button { vm.rotateSelected() } label: {
                    Image(systemName: "rotate.right").font(.system(size: 14))
                        .foregroundColor(Color(red: 0.7, green: 0.5, blue: 0.9))
                        .frame(width: 32, height: 32)
                        .background(Color(red: 0.7, green: 0.5, blue: 0.9).opacity(0.15))
                        .overlay(Rectangle().stroke(Color(red: 0.7, green: 0.5, blue: 0.9).opacity(0.4), lineWidth: 1))
                }.buttonStyle(.plain)

                Button { vm.deleteSelected() } label: {
                    Image(systemName: "trash.fill").font(.system(size: 14))
                        .foregroundColor(.red)
                        .frame(width: 32, height: 32)
                        .background(Color.red.opacity(0.15))
                        .overlay(Rectangle().stroke(Color.red.opacity(0.4), lineWidth: 1))
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color(red: 0.10, green: 0.11, blue: 0.14))
        .overlay(Rectangle().stroke(def.category.color.opacity(0.3), lineWidth: 1), alignment: .top)
    }

    /// 配方选择：机器有真实配方数据才显示，选完立即重新计算产能统计
    @ViewBuilder
    private func recipePicker(for def: BuildingDefinition) -> some View {
        let recipes = vm.availableRecipes(for: def)
        if !recipes.isEmpty, let placedID = vm.selectedBuildingID {
            let currentIndex = vm.selectedPlaced?.selectedRecipeIndex
            Menu {
                ForEach(Array(recipes.enumerated()), id: \.offset) { idx, recipe in
                    Button {
                        vm.selectRecipe(idx, for: placedID)
                    } label: {
                        let outputText = recipe.outputs.map { "\($0.name)×\($0.count)" }.joined(separator: "+")
                        Text("\(outputText)（\(recipe.time)s）")
                    }
                }
            } label: {
                Label(
                    currentIndex.flatMap { recipes.indices.contains($0) ? recipes[$0].outputs.first?.name : nil } ?? "选择配方",
                    systemImage: "list.bullet.rectangle"
                )
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Color(red: 0.4, green: 0.8, blue: 0.2))
            }
        }
    }

    /// 仓库取货口的材料选择：只对取货口显示（存货口是入口，接收任意材料，不用选），选完立即重新计算产能统计
    @ViewBuilder
    private func outletMaterialPicker(for def: BuildingDefinition) -> some View {
        if def.id == BuildingDefinition.warehouseOutletID, let placedID = vm.selectedBuildingID {
            let current = vm.selectedPlaced?.outletMaterial
            Menu {
                Button {
                    vm.setOutletMaterial(nil, for: placedID)
                } label: {
                    Text("未设置")
                }
                ForEach(vm.solidMaterials, id: \.self) { material in
                    Button {
                        vm.setOutletMaterial(material, for: placedID)
                    } label: {
                        Text(material)
                    }
                }
            } label: {
                Label(current ?? "选择材料", systemImage: "shippingbox.fill")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color(red: 0.4, green: 0.8, blue: 0.2))
            }
        }
    }

    // MARK: - 保存 Toast
    private var saveToast: some View {
        VStack {
            Spacer()
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Color(red: 0.4, green: 0.8, blue: 0.2))
                Text("布局已保存")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            .background(ZStack {
                Rectangle().fill(Color(red: 0.10, green: 0.11, blue: 0.14))
                Rectangle().stroke(Color(red: 0.4, green: 0.8, blue: 0.2).opacity(0.6), lineWidth: 1.5)
            })
            .shadow(color: Color(red: 0.4, green: 0.8, blue: 0.2).opacity(0.3), radius: 8)
            .padding(.bottom, 80)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation { vm.showSaveConfirm = false }
                }
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .allowsHitTesting(false)
    }
}

#Preview {
    FactoryLayoutView()
}
