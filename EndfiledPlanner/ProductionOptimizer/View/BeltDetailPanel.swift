// Created by Jinjia Ou on 10/2/26.

import SwiftUI

/// 选中传送带/管道的详情面板：速度上限、长度、实际流量和货物、两头接到哪、删这一格/删整条。
/// 布局跟建筑详情面板一样（iPad 右侧、iPhone 底部可收起）
struct BeltDetailPanel: View {
    @ObservedObject var vm: FactoryViewModel
    let belt: Belt
    let style: BuildingDetailPanel.Style

    @State private var expanded = true
    @State private var confirmDeleteWhole = false

    private let green = Color(red: 0.4, green: 0.8, blue: 0.2)
    private let orange = Color(red: 0.9, green: 0.5, blue: 0.2)
    private let red = Color(red: 0.9, green: 0.3, blue: 0.2)
    private var lineColor: Color {
        belt.lineType == .belt ? Color(red: 1.0, green: 0.55, blue: 0.1) : Color(red: 0.3, green: 0.6, blue: 1.0)
    }

    private var flow: FlowSimulator.BeltFlow? { vm.stats.beltFlows[belt.id] }
    private var capacityPerMin: Double {
        (belt.lineType == .belt ? FlowSimulator.beltCapacity : FlowSimulator.pipeCapacity) * 60
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if style == .side || expanded {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) { content }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
                .frame(maxHeight: style == .bottom ? 260 : .infinity)
            }
        }
        .background(Color(red: 0.10, green: 0.11, blue: 0.14))
        .overlay(Rectangle().stroke(lineColor.opacity(0.35), lineWidth: 1))
        .alert("删除整条\(belt.lineType.displayName)？", isPresented: $confirmDeleteWhole) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { vm.deleteSelectedBelt() }
        } message: {
            Text("共 \(belt.segments.count) 格，删除后可以撤销。")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ZStack {
                    Rectangle().fill(lineColor.opacity(0.2)).frame(width: 40, height: 40)
                    Rectangle().stroke(lineColor.opacity(0.6), lineWidth: 1.5).frame(width: 40, height: 40)
                    Image(systemName: belt.lineType == .belt ? "arrow.left.and.right" : "drop.fill")
                        .font(.system(size: 16)).foregroundColor(lineColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(belt.lineType.displayName).font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                    Text(String(format: "长 %d 格 · 上限 %.0f/min", belt.segments.count, capacityPerMin))
                        .font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.55))
                }
                Spacer()
                if style == .bottom {
                    iconButton(expanded ? "chevron.down" : "chevron.up") {
                        withAnimation(.spring(response: 0.3)) { expanded.toggle() }
                    }
                }
                iconButton("xmark") { vm.clearBeltSelection() }
            }
            statusBar
            HStack(spacing: 8) {
                if vm.selectedBeltCell != nil {
                    actionButton("删除这一格", icon: "scissors", color: orange) { vm.deleteSelectedBeltCell() }
                }
                actionButton("删除整条", icon: "trash.fill", color: red) { confirmDeleteWhole = true }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color(red: 0.08, green: 0.09, blue: 0.12))
    }

    /// 状态：没接到出口 / 没接到入口 / 被限流（满） / 运行中 / 空闲
    private var statusBar: some View {
        let (label, color): (String, Color) = {
            guard let flow else { return ("线头没接到任何出口，没有货", .white.opacity(0.45)) }
            if flow.toName == nil { return ("线尾没接到任何入口，货送不出去", red) }
            if flow.isOverCapacity { return ("满载（上游想送的比上限多，被限流）", orange) }
            if flow.total < 1e-9 { return ("空闲（没有货在跑）", .white.opacity(0.45)) }
            return ("运行中", green)
        }()
        let ratio = (flow?.total ?? 0) * 60 / capacityPerMin
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.system(size: 11, weight: .bold)).foregroundColor(color)
                Spacer()
                Text(String(format: "%.1f / %.0f /min", (flow?.total ?? 0) * 60, capacityPerMin))
                    .font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.white.opacity(0.08))
                    Rectangle().fill(color).frame(width: geo.size.width * max(0, min(1, ratio)))
                }
            }
            .frame(height: 4)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let flow {
            VStack(alignment: .leading, spacing: 6) {
                Text("连接").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(.white.opacity(0.45))
                Text("\(flow.fromName) → \(flow.toName ?? "（未接）")")
                    .font(.system(size: 12)).foregroundColor(.white.opacity(0.85))
            }
            let items = flow.flow.filter { $0.value > 1e-9 }
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("货物").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(.white.opacity(0.45))
                    ForEach(items.keys.sorted(), id: \.self) { item in
                        HStack(spacing: 6) {
                            ItemIcon(name: item, size: 20)
                            Text(item).font(.system(size: 12)).foregroundColor(.white.opacity(0.85))
                            Spacer()
                            Text(String(format: "%.1f /min", (items[item] ?? 0) * 60))
                                .font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(green)
                        }
                    }
                }
            }
        } else {
            Text("把线头接到建筑出口（或分流器、汇流器等）才会有货在线上跑。")
                .font(.system(size: 11)).foregroundColor(.white.opacity(0.6))
        }
    }

    private func iconButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 13, weight: .bold)).foregroundColor(.white.opacity(0.6))
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
    }

    private func actionButton(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
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
    }
}
