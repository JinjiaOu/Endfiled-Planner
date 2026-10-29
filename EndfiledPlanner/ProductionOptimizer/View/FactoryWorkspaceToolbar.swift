// Created by Jinjia Ou on 10/19/26.

import SwiftUI

/// 文档动作与编辑工具分开，保留原来的 ViewModel 状态切换。
struct FactoryWorkspaceHeader: View {
    @ObservedObject var vm: FactoryViewModel
    var buildingPaletteVisible: Bool

    private var modeTitle: String {
        if case .place(let def) = vm.editMode, vm.pendingPlacement == nil {
            return String(localized: "点画布放置：\(def.displayName)")
        }
        if buildingPaletteVisible { return String(localized: "选择要建造的设施") }
        if vm.pendingPlacement != nil { return String(localized: "放置我的布局") }
        switch vm.editMode {
        case .select: return String(localized: "选择与查看")
        case .place: return String(localized: "放置建筑")
        case .belt: return String(localized: "连接传送带")
        case .pipe: return String(localized: "连接管道")
        case .erase: return String(localized: "删除模式 · 划过即可删除")
        case .boxSelect: return String(localized: "框选与整组编辑")
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.xs) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppSpacing.xs) {
                    mapLabel
                    Rectangle().fill(AppColors.border).frame(width: 1, height: 12)
                    modeLabel
                }
                .fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    mapLabel
                    modeLabel
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            historyActions
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.xxs)
        .background(AppColors.surface)
        .overlay(alignment: .bottom) { Divider().overlay(AppColors.border) }
    }

    private var mapLabel: some View {
        Text(vm.layout.mapType.displayName)
            .font(AppTypography.rowTitle).foregroundStyle(AppColors.primaryText)
    }

    private var modeLabel: some View {
        Text(modeTitle).font(AppTypography.caption)
            .foregroundStyle(vm.editMode == .erase ? AppColors.error : AppColors.secondaryText)
    }

    private var historyActions: some View {
        HStack(spacing: 0) {
            AppIconButton(title: String(localized: "撤销"), systemImage: "arrow.uturn.backward") { vm.undo() }
                .disabled(!vm.canUndo)
            AppIconButton(title: String(localized: "重做"), systemImage: "arrow.uturn.forward") { vm.redo() }
                .disabled(!vm.canRedo)
            AppIconButton(title: String(localized: "保存画布"), systemImage: "square.and.arrow.down") { vm.saveLayout() }
        }
    }
}

struct FactoryWorkspaceToolbar: View {
    @ObservedObject var vm: FactoryViewModel
    @Binding var showBuildingPalette: Bool
    @Binding var showMyLayouts: Bool
    var horizontalLabels = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView(.horizontal) {
                    HStack(spacing: 0) { tools }.padding(.horizontal, AppSpacing.xs)
                }
                .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 0) { tools }.padding(.horizontal, AppSpacing.xxs)
            }
        }
        .background(AppColors.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(AppColors.border).frame(height: 1).allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var tools: some View {
        tool(String(localized: "选择"), icon: "cursorarrow", active: vm.editMode == .select && !showBuildingPalette) {
            vm.editMode = .select
            showBuildingPalette = false
        }
        tool(String(localized: "建造"), icon: "plus.square", active: buildingActive) {
            withAnimation(AppMotion.panel(reduceMotion: reduceMotion)) {
                showBuildingPalette.toggle()
                vm.editMode = .select
            }
        }
        tool(String(localized: "传送带"), icon: "arrow.left.and.right", active: vm.editMode == .belt) {
            vm.editMode = .belt
            showBuildingPalette = false
            vm.beltStart = nil
        }
        if vm.layout.mapType.rules.allowsPipes {
            tool(String(localized: "管道"), icon: "water.waves", active: vm.editMode == .pipe) {
                vm.editMode = .pipe
                showBuildingPalette = false
                vm.beltStart = nil
            }
        }
        tool(String(localized: "框选"), icon: "rectangle.dashed", active: vm.editMode == .boxSelect) {
            vm.editMode = .boxSelect
            showBuildingPalette = false
        }
        tool(String(localized: "我的布局"), icon: "square.stack.3d.up", active: showMyLayouts) { showMyLayouts = true }
        tool(String(localized: "删除"), icon: "trash", active: vm.editMode == .erase) {
            vm.editMode = .erase
            showBuildingPalette = false
        }
    }

    private var buildingActive: Bool {
        if case .place = vm.editMode { return true }
        return showBuildingPalette
    }

    private func tool(_ title: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if horizontalLabels && !dynamicTypeSize.isAccessibilitySize {
                    HStack(spacing: AppSpacing.xs) { toolLabel(title, icon: icon, active: active) }
                } else {
                    VStack(spacing: AppSpacing.xxs) { toolLabel(title, icon: icon, active: active) }
                }
            }
            .foregroundStyle(active ? AppColors.accent : AppColors.secondaryText)
            .padding(.horizontal, AppSpacing.xxs)
            .padding(.vertical, AppSpacing.xs)
            .frame(minWidth: AppSize.touchTarget, maxWidth: .infinity, minHeight: AppSize.touchTarget)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if active {
                    Rectangle().fill(AppColors.accent).frame(width: 18, height: 2)
                        .allowsHitTesting(false)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
    @ViewBuilder
    private func toolLabel(_ title: String, icon: String, active: Bool) -> some View {
        Image(systemName: icon).font(.body.weight(.medium))
        Text(title).font(.caption2.weight(active ? .semibold : .regular))
            .fixedSize(horizontal: false, vertical: true)
    }

}
