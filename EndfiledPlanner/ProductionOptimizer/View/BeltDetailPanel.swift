// Created by Jinjia Ou on 10/2/26.

import SwiftUI

/// 非模态线路检查器；流量、上限和删除行为沿用原实现。
struct BeltDetailPanel: View {
    @ObservedObject var vm: FactoryViewModel
    let belt: Belt
    let style: BuildingDetailPanel.Style
    var maxContentHeight: CGFloat = 260
    var maxPanelHeight: CGFloat? = nil

    @State private var expanded = false
    @State private var confirmDeleteWhole = false

    private var flow: FlowSimulator.BeltFlow? { vm.stats.beltFlows[belt.id] }
    private var capacityPerMin: Double {
        (belt.lineType == .belt ? FlowSimulator.beltCapacity : FlowSimulator.pipeCapacity) * 60
    }

    var body: some View {
        AppInspectorContainer(title: belt.lineType.displayName,
                              subtitle: String(localized: "长 \(belt.segments.count) 格 · 上限 \(String(format: "%.0f", capacityPerMin))/min"),
                              placement: style == .side ? .side : .bottom,
                              isExpanded: $expanded,
                              maxContentHeight: style == .bottom ? maxContentHeight : nil,
                              maxPanelHeight: style == .bottom ? maxPanelHeight : nil,
                              summaryText: status.title,
                              disclosureTitle: String(localized: "连接、货物与流量"),
                              onClose: { vm.clearBeltSelection() }) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                statusBar
                content
            }
        } actions: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppSpacing.xs) { deleteActions }
                VStack(alignment: .leading, spacing: AppSpacing.xs) { deleteActions }
            }
        }
        .alert(String(localized: "删除整条\(belt.lineType.displayName)？"), isPresented: $confirmDeleteWhole) {
            Button(String(localized: "取消"), role: .cancel) {}
            Button(String(localized: "删除"), role: .destructive) { vm.deleteSelectedBelt() }
        } message: {
            Text(String(localized: "共 \(belt.segments.count) 格，删除后可以撤销。"))
        }
    }

    @ViewBuilder
    private var deleteActions: some View {
        if vm.selectedBeltCell != nil {
            Button { vm.deleteSelectedBeltCell() } label: { Label(String(localized: "删除这一格"), systemImage: "scissors") }
                .buttonStyle(AppActionStyle(emphasis: .secondary))
        }
        Button { confirmDeleteWhole = true } label: { Label(String(localized: "删除整条"), systemImage: "trash") }
            .buttonStyle(AppActionStyle(emphasis: .destructive))
    }

    private var status: (title: String, tone: AppStatusTone) {
        guard let flow else { return (String(localized: "线头没接到任何出口，没有货"), .neutral) }
        if flow.toName == nil { return (String(localized: "线尾没接到任何入口，货送不出去"), .error) }
        if flow.isOverCapacity { return (String(localized: "满载（上游想送的比上限多，被限流）"), .warning) }
        if flow.total < 1e-9 { return (String(localized: "空闲（没有货在跑）"), .neutral) }
        return (String(localized: "运行中"), .success)
    }

    private var statusBar: some View {
        let ratio = (flow?.total ?? 0) * 60 / capacityPerMin
        return VStack(alignment: .leading, spacing: AppSpacing.sm) {
            AppInlineNotice(title: status.title, tone: status.tone)
            AppKeyValueRow(title: String(localized: "流量 / 上限"),
                           value: String(format: "%.1f / %.0f /min", (flow?.total ?? 0) * 60, capacityPerMin))
            ProgressView(value: max(0, min(1, ratio)))
                .tint(status.tone.color)
                .accessibilityLabel(String(localized: "线路利用率"))
        }
    }

    @ViewBuilder
    private var content: some View {
        if let flow {
            AppKeyValueRow(title: String(localized: "连接"), value: String(localized: "\(DisplayName.device(flow.fromName)) → \(flow.toName.map(DisplayName.device) ?? String(localized: "（未接）"))"))
            let items = flow.flow.filter { $0.value > 1e-9 }
            if !items.isEmpty {
                AppSectionHeader(title: String(localized: "货物"))
                ForEach(items.keys.sorted(), id: \.self) { item in
                    HStack(alignment: .top, spacing: AppSpacing.xs) {
                        ItemIcon(name: item, size: AppSize.icon)
                        AppKeyValueRow(title: DisplayName.item(item), value: String(format: "%.1f /min", (items[item] ?? 0) * 60))
                    }
                }
            }
        } else {
            AppInlineNotice(title: String(localized: "连接出口后开始输送"), message: String(localized: "把线头接到建筑出口（或分流器、汇流器等）才会有货在线上跑。"))
        }
    }
}
