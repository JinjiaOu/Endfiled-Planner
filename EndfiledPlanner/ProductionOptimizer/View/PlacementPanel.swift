//
//  PlacementPanel.swift
//  EndfiledPlanner
//

import SwiftUI

/// 摆"我的布局"时的面板：布局名、能不能放、旋转 / 取消 / 确认。
/// iPad 放右侧浮层，iPhone 放在网格下方
struct PlacementPanel: View {
    @ObservedObject var vm: FactoryViewModel

    private let green = Color(red: 0.4, green: 0.8, blue: 0.2)
    private let red = Color(red: 0.9, green: 0.3, blue: 0.2)
    private let purple = Color(red: 0.7, green: 0.5, blue: 0.9)

    var body: some View {
        if let placement = vm.pendingPlacement {
            let blocked = vm.placementBlockedReason
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    LayoutThumbnail(layout: placement.saved)
                        .frame(width: 40, height: 40)
                        .background(Color(red: 0.06, green: 0.07, blue: 0.10))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("放置：\(placement.saved.name)")
                            .font(.system(size: 15, weight: .bold)).foregroundColor(.white).lineLimit(1)
                        Text(blocked ?? "按住虚影拖动，或点画布上的位置把虚影挪过去；拖到画面边缘会自动滚动")
                            .font(.system(size: 10))
                            .foregroundColor(blocked == nil ? .white.opacity(0.6) : red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
                HStack(spacing: 8) {
                    actionButton("旋转 90°", icon: "rotate.right", color: purple, enabled: true) { vm.rotatePlacement() }
                    actionButton("取消", icon: "xmark.circle", color: .white.opacity(0.7), enabled: true) { vm.cancelPlacement() }
                    actionButton("确认放置", icon: "checkmark.circle.fill", color: green, enabled: blocked == nil) {
                        vm.confirmPlacement()
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Color(red: 0.08, green: 0.09, blue: 0.12))
            .overlay(Rectangle().stroke(green.opacity(0.35), lineWidth: 1))
        }
    }

    private func actionButton(_ title: String, icon: String, color: Color, enabled: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 14))
                Text(title).font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(color)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(color.opacity(0.12))
            .overlay(Rectangle().stroke(color.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }
}
