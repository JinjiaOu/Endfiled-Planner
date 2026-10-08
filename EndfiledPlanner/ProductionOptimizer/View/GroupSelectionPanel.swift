//
//  GroupSelectionPanel.swift
//  EndfiledPlanner
//

import SwiftUI

/// 框选模式的面板：已选几个建筑 + 删除 / 存为布局 / 取消选择。
/// iPad 放右侧浮层，iPhone 放在网格下方，跟 BuildingDetailPanel 一样
struct GroupSelectionPanel: View {
    enum Style { case side, bottom }

    @ObservedObject var vm: FactoryViewModel
    let style: Style

    private let groupColor = Color(red: 0.3, green: 0.85, blue: 0.95)
    private let red = Color(red: 0.9, green: 0.3, blue: 0.2)
    private let green = Color(red: 0.4, green: 0.8, blue: 0.2)

    var body: some View {
        let count = vm.groupSelection.count
        let beltCount = vm.groupBeltSelection.count
        let title: String = {
            switch (count, beltCount) {
            case (0, 0): return "框选"
            case (_, 0): return "已选 \(count) 个建筑"
            case (0, _): return "已选 \(beltCount) 条线"
            default:     return "已选 \(count) 个建筑、\(beltCount) 条线"
            }
        }()
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.dashed")
                    .font(.system(size: 17))
                    .foregroundColor(groupColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                    Text(!vm.hasGroupSelection
                         ? "在空地上拖出一个框，整个落在框里的建筑和线会被选中，拖到画面边缘会自动滚动；点单个建筑或线也能加入/移出"
                         : "按住任一选中的建筑或线拖动整组；继续拉框或点建筑/线可以加入/移出")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button {
                    vm.editMode = .select
                } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 8) {
                actionButton("删除", icon: "trash.fill", color: red, enabled: vm.hasGroupSelection) { vm.deleteGroup() }
                // 存为布局在 M4 第 2 步做
                actionButton("存为布局", icon: "square.and.arrow.down.on.square", color: green, enabled: false) {}
                actionButton("取消选择", icon: "xmark.circle", color: .white.opacity(0.7), enabled: vm.hasGroupSelection) {
                    vm.clearGroupSelection()
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color(red: 0.08, green: 0.09, blue: 0.12))
        .overlay(Rectangle().stroke(groupColor.opacity(0.35), lineWidth: 1))
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
