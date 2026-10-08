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

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var vm = FactoryViewModel()

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

    // 其他
    @State private var showClearConfirm = false
    @State private var pendingMapSwitch: MapType? = nil
    @State private var pendingPreset: FactoryPreset? = nil

    // 我的布局
    @StateObject private var myLayouts = MyLayoutStore()
    @State private var showMyLayouts = false
    @State private var showSaveGroupPrompt = false
    @State private var saveGroupName = ""

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
                                    dragLocationInGrid: $dragLocationInGrid,
                                    autoScrollFinger: $autoScrollFinger
                                )
                                .padding(20)
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
                        } else if !usesSidePalette, vm.editMode == .boxSelect {
                            GroupSelectionPanel(vm: vm, style: .bottom, onSaveAs: promptSaveGroup)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        } else if !usesSidePalette, let placed = vm.selectedPlaced, let def = vm.selectedDefinition {
                            BuildingDetailPanel(vm: vm, placed: placed, def: def, style: .bottom)
                                .id(placed.id)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        } else if !usesSidePalette, let belt = vm.selectedBelt {
                            BeltDetailPanel(vm: vm, belt: belt, style: .bottom)
                                .id(belt.id)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .animation(.spring(response: 0.3), value: showBuildingPalette)
                    .animation(.spring(response: 0.3), value: vm.selectedBuildingID)
                    .animation(.spring(response: 0.3), value: vm.selectedBeltID)
                    .animation(.spring(response: 0.3), value: vm.editMode == .boxSelect)
                }

                if showBuildingPalette && usesSidePalette {
                    sideBuildingPalette
                } else if usesSidePalette, vm.editMode == .boxSelect {
                    HStack {
                        Spacer()
                        GroupSelectionPanel(vm: vm, style: .side, onSaveAs: promptSaveGroup)
                            .frame(width: 360)
                            .padding(.trailing, 18)
                            .padding(.top, 64)
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(3)
                } else if usesSidePalette, let placed = vm.selectedPlaced, let def = vm.selectedDefinition {
                    HStack {
                        Spacer()
                        BuildingDetailPanel(vm: vm, placed: placed, def: def, style: .side)
                            .id(placed.id)
                            .frame(width: 360)
                            .padding(.trailing, 18)
                            .padding(.top, 64)
                            .padding(.bottom, 18)
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(3)
                } else if usesSidePalette, let belt = vm.selectedBelt {
                    HStack {
                        Spacer()
                        BeltDetailPanel(vm: vm, belt: belt, style: .side)
                            .id(belt.id)
                            .frame(width: 360)
                            .frame(maxHeight: 420, alignment: .top)
                            .padding(.trailing, 18)
                            .padding(.top, 64)
                        Spacer().frame(width: 0)
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(3)
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
                            Label("保存画布", systemImage: "square.and.arrow.down")
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
                            .foregroundColor(Color(red: 1.0, green: 0.8, blue: 0.0))
                    }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color(red: 0.08, green: 0.09, blue: 0.12), for: .navigationBar)
            .alert("存为布局", isPresented: $showSaveGroupPrompt) {
                TextField("布局名字", text: $saveGroupName)
                Button("取消", role: .cancel) {}
                Button("保存") { saveGroup() }
            } message: {
                Text("选中的建筑、它们的设置和跟着它们走的线会一起存下来")
            }
            .sheet(isPresented: $showMyLayouts) {
                MyLayoutsView(store: myLayouts, currentMap: vm.layout.mapType)
            }
            .modifier(FactoryAlertsModifier(vm: vm, showClearConfirm: $showClearConfirm,
                                           pendingPreset: $pendingPreset,
                                           pendingMapSwitch: $pendingMapSwitch))
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
            // 不能用管道的地图（四号谷地）不显示管道工具
            if vm.layout.mapType.rules.allowsPipes {
                Divider().overlay(Color.white.opacity(0.1))
                toolButton(icon: "water.waves", label: "管道",
                           isActive: vm.editMode == .pipe,
                           color: Color(red: 0.3, green: 0.7, blue: 1.0)) {
                    vm.editMode = .pipe
                    showBuildingPalette = false
                    vm.beltStart = nil
                }
            }
            Divider().overlay(Color.white.opacity(0.1))
            // 旋转已选建筑在详情面板里，放置前旋转在建造面板里，这个位置给框选
            toolButton(icon: "rectangle.dashed", label: "框选",
                       isActive: vm.editMode == .boxSelect,
                       color: Color(red: 0.3, green: 0.85, blue: 0.95)) {
                vm.editMode = .boxSelect
                showBuildingPalette = false
            }
            Divider().overlay(Color.white.opacity(0.1))
            toolButton(icon: "square.stack.3d.up", label: "我的布局",
                       isActive: showMyLayouts,
                       color: Color(red: 0.4, green: 0.8, blue: 0.2)) {
                showMyLayouts = true
            }
            Divider().overlay(Color.white.opacity(0.1))
            toolButton(icon: "trash.fill", label: "删除",
                       isActive: vm.editMode == .erase,
                       color: Color.red) {
                vm.editMode = .erase
                showBuildingPalette = false
            }
            Divider().overlay(Color.white.opacity(0.1))
            toolButton(icon: "arrow.uturn.backward", label: "撤销",
                       isActive: false,
                       color: .white) {
                vm.undo()
            }
            .disabled(!vm.canUndo)
            .opacity(vm.canUndo ? 1 : 0.35)
            Divider().overlay(Color.white.opacity(0.1))
            toolButton(icon: "arrow.uturn.forward", label: "重做",
                       isActive: false,
                       color: .white) {
                vm.redo()
            }
            .disabled(!vm.canRedo)
            .opacity(vm.canRedo ? 1 : 0.35)
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
                Text("按住建筑再拖到网格放置 · 双指缩放")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
                Spacer().frame(width: 12)
                // 放置前旋转（已放下的建筑在详情面板里旋转）
                Button {
                    vm.pendingRotation = vm.pendingRotation.next
                } label: {
                    Label("旋转 \(vm.pendingRotation.symbol)", systemImage: "rotate.right")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(red: 0.7, green: 0.5, blue: 0.9))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color(red: 0.7, green: 0.5, blue: 0.9).opacity(0.12))
                }
                .buttonStyle(.plain)
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
        // 协议核心每张图自动生成、全局唯一，不放进建造面板里让人手动摆第二个
        let onMap = BuildingDefinition.all.filter { $0.isAvailable(on: vm.layout.mapType) && !$0.isProtocolCore }
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

    /// 建筑卡片：按住再拖时激活拖拽状态，松手时在网格对应位置放置
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
        // 先按住 0.2 秒再拖才算"拿建筑去放置"，手指一按下就滑动则交给外面的 ScrollView 滚动。
        // SwiftUI 自己的 DragGesture / 长按+拖（不管 gesture 还是 simultaneousGesture）在新版 iOS 上
        // 都会把卡片区域的列表滑动吃掉，所以改用 UIKit 的长按手势：它和 ScrollView 的滑动是同一套
        // 手势系统，按下就滑时长按自动失败，滚动不受影响；长按成功后手指移动会持续回调位置。
        // 原来长按弹出的"旋转"菜单会跟这个冲突，去掉了，放置前旋转用工具栏的旋转按钮
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

                // 内容可能很长（建筑一多，"没正常运行的机器"这类提示行会刷很多条），
                // 之前没套 ScrollView 会直接顶出屏幕、连最上面的功率数字都划不到
                ScrollView {
                    FactoryStatsView(stats: vm.stats, isExpanded: .constant(true))
                }
            }
            .background(Color(red: 0.10, green: 0.11, blue: 0.14))
            .overlay(Rectangle().stroke(Color(red: 0.4, green: 0.8, blue: 0.2).opacity(0.4), lineWidth: 1))
            .frame(maxWidth: 340)
            .frame(maxHeight: 480)
            .padding(.trailing, 16)
            .padding(.bottom, 80)   // 留出悬浮按钮空间
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .bottomTrailing)))
    }

    // MARK: - 保存 Toast
    private var saveToast: some View {
        VStack {
            Spacer()
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Color(red: 0.4, green: 0.8, blue: 0.2))
                Text(vm.toastText)
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
