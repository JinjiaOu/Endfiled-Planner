// Created by Jinjia Ou on 10/19/26.

import SwiftUI

struct GroupSelectionPanel: View {
    enum Style { case side, bottom }
    @ObservedObject var vm: FactoryViewModel
    let style: Style
    var maxPanelHeight: CGFloat? = nil
    var onSaveAs: () -> Void = {}
    @State private var expanded = true

    private var title: String {
        let count = vm.groupSelection.count
        let beltCount = vm.groupBeltSelection.count
        switch (count, beltCount) {
        case (0, 0): return String(localized: "框选")
        case (_, 0): return String(localized: "已选 \(count) 个建筑")
        case (0, _): return String(localized: "已选 \(beltCount) 条线")
        default: return String(localized: "已选 \(count) 个建筑、\(beltCount) 条线")
        }
    }

    var body: some View {
        AppInspectorContainer(title: title, placement: style == .side ? .side : .bottom,
                              isExpanded: $expanded, maxContentHeight: style == .bottom ? 120 : nil,
                              maxPanelHeight: style == .bottom ? maxPanelHeight : nil,
                              onClose: { vm.editMode = .select }) {
            Text(!vm.hasGroupSelection
                 ? String(localized: "在空地上拖出一个框，整个落在框里的建筑和线会被选中，拖到画面边缘会自动滚动；点单个建筑或线也能加入/移出")
                 : String(localized: "按住任一选中的建筑或线拖动整组；继续拉框或点建筑/线可以加入/移出"))
                .font(AppTypography.supporting).foregroundStyle(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        } actions: {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: AppSpacing.xs)], spacing: AppSpacing.xs) {
                Button { vm.deleteGroup() } label: { Label(String(localized: "删除"), systemImage: "trash") }
                    .buttonStyle(AppActionStyle(emphasis: .destructive)).disabled(!vm.hasGroupSelection)
                Button(action: onSaveAs) { Label(String(localized: "存为布局"), systemImage: "square.and.arrow.down.on.square") }
                    .buttonStyle(AppActionStyle(emphasis: .secondary)).disabled(vm.groupSelection.isEmpty)
                Button { vm.clearGroupSelection() } label: { Label(String(localized: "取消选择"), systemImage: "xmark.circle") }
                    .buttonStyle(AppActionStyle(emphasis: .secondary)).disabled(!vm.hasGroupSelection)
            }
        }
    }
}
