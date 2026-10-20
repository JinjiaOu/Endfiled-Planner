// Created by Jinjia Ou on 10/19/26.

import SwiftUI

struct PlacementPanel: View {
    @ObservedObject var vm: FactoryViewModel
    var style: BuildingDetailPanel.Style = .bottom
    var maxPanelHeight: CGFloat? = nil
    @State private var expanded = true

    var body: some View {
        if let placement = vm.pendingPlacement {
            let blocked = vm.placementBlockedReason
            AppInspectorContainer(title: "放置：\(placement.saved.name)",
                                  subtitle: blocked == nil ? "可放置" : "当前位置不可放置",
                                  placement: style == .side ? .side : .bottom,
                                  isExpanded: $expanded, maxContentHeight: style == .bottom ? 120 : nil,
                              maxPanelHeight: style == .bottom ? maxPanelHeight : nil,
                                  onClose: { vm.cancelPlacement() }) {
                HStack(alignment: .top, spacing: AppSpacing.sm) {
                    LayoutThumbnail(layout: placement.saved)
                        .frame(width: AppSize.touchTarget, height: AppSize.touchTarget)
                        .background(AppColors.canvas).accessibilityHidden(true)
                    AppInlineNotice(title: blocked == nil ? "移动布局预览" : "放置受阻",
                                    message: blocked ?? "按住虚影拖动，或点画布上的位置把虚影挪过去；拖到画面边缘会自动滚动",
                                    tone: blocked == nil ? .info : .error)
                }
            } actions: {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: AppSpacing.xs)], spacing: AppSpacing.xs) {
                    Button { vm.rotatePlacement() } label: { Label("旋转 90°", systemImage: "rotate.right") }
                        .buttonStyle(AppActionStyle(emphasis: .secondary))
                    Button { vm.cancelPlacement() } label: { Label("取消", systemImage: "xmark.circle") }
                        .buttonStyle(AppActionStyle(emphasis: .secondary))
                    Button { vm.confirmPlacement() } label: { Label("确认放置", systemImage: "checkmark.circle") }
                        .buttonStyle(AppActionStyle()).disabled(blocked != nil)
                }
            }
        }
    }
}
