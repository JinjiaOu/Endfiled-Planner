// Created by Jinjia Ou on 4/3/26.

import SwiftUI

struct FactoryStatsView: View {
    let stats: FactoryGridModel.ProductionStats
    @Binding var isExpanded: Bool
    var showsHeader = true
    /// 当前高亮的产物（行加选中态）；onSelectItem 为 nil 时产物行不可点
    var highlightedItem: String? = nil
    var onSelectItem: ((String) -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            if showsHeader {
                Button {
                    withAnimation(AppMotion.panel(reduceMotion: reduceMotion)) { isExpanded.toggle() }
                } label: {
                    HStack(alignment: .top, spacing: AppSpacing.xs) {
                        AppSectionHeader(title: "产能统计", subtitle: String(format: "电力余量 %+.1f MW", powerMargin))
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .foregroundStyle(AppColors.accent)
                    }
                    .frame(minHeight: AppSize.touchTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(isExpanded ? "已展开" : "已折叠")
            }
            if isExpanded {
                summary
                diagnostics
                logistics
                lines
                categories
            }
        }
        .padding(AppSpacing.md)
        .background(AppColors.surface)
    }

    private var powerMargin: Double { stats.totalPowerGenerated - stats.totalPowerConsumed }

    private var summary: some View {
        AppMetricGrid {
            AppMetricCell(title: "建筑", value: "\(stats.buildingCount)", unit: "总数")
            AppMetricCell(title: "总发电量", value: String(format: "%.0f", stats.totalPowerGenerated), unit: "MW")
            AppMetricCell(title: "用电量", value: String(format: "%.0f", stats.totalPowerConsumed), unit: "MW")
            AppMetricCell(title: "产线", value: "\(stats.productionLines.count)", unit: "条")
            AppMetricCell(title: "电力余量", value: String(format: "%+.1f", powerMargin), unit: "MW",
                          tone: powerMargin >= 0 ? .success : .error)
        }
    }

    @ViewBuilder
    private var diagnostics: some View {
        if stats.bottleneck != nil || stats.powerShortage > 1e-6 || stats.unpoweredCount > 0
            || !stats.flowConverged || stats.machineStates.contains(where: { $0.status != .running }) {
            Divider().overlay(AppColors.border)
            AppSectionHeader(title: "运行诊断", subtitle: "异常原因与当前模拟状态")
            if let bottleneck = stats.bottleneck {
                AppInlineNotice(title: "瓶颈", message: bottleneck, tone: .warning)
            }
            if stats.powerShortage > 1e-6 {
                AppInlineNotice(title: "电力不足", message: String(format: "还差 %.1f MW", stats.powerShortage), tone: .error)
            }
            if stats.unpoweredCount > 0 {
                AppInlineNotice(title: "未通电 ×\(stats.unpoweredCount)",
                                message: "不在供电桩范围内，不运行", tone: .error)
            }
            if !stats.flowConverged {
                AppInlineNotice(title: "流量模拟未收敛", message: "可能有环路，数字仅供参考", tone: .error)
            }
            ForEach(stats.machineStates.filter { $0.status != .running }) { machine in
                noticeRow(icon: "gearshape.fill", text: machineStateText(machine), color: AppColors.warning)
            }
        }
    }

    @ViewBuilder
    private var logistics: some View {
        Divider().overlay(AppColors.border)
        AppSectionHeader(title: "电力与物流")
        if stats.totalPowerGenerated > 0 || stats.totalPowerConsumed > 0 {
            noticeRow(icon: "bolt.horizontal.fill", text: powerText(stats), color: AppColors.accent)
        }
        if stats.passthroughCount > 0 {
            noticeRow(icon: "arrow.triangle.branch",
                      text: "直通节点 ×\(stats.passthroughCount)（分流器/汇流器等，不计入产线）", color: AppColors.info)
        }
        if !stats.outletMaterials.isEmpty {
            noticeRow(icon: "shippingbox.fill", text: "仓库取线：\(stats.outletMaterials.joined(separator: "、"))",
                      color: AppColors.success)
        }
        ForEach(stats.sinkStates) { sink in
            noticeRow(icon: "tray.and.arrow.down.fill", text: sinkText(sink),
                      itemNames: sink.consumed.filter { $0.value > 1e-9 }.map(\.key).sorted(), color: AppColors.info)
        }
    }

    @ViewBuilder
    private var lines: some View {
        if !stats.productionLines.isEmpty {
            Divider().overlay(AppColors.border)
            AppSectionHeader(title: "产出产线", subtitle: onSelectItem != nil ? "点产物在画布上高亮相关机器和线" : nil)
            ForEach(stats.productionLines, id: \.output) { line in productionLineRow(line: line) }
        }
        if !stats.consumptionLines.isEmpty {
            Divider().overlay(AppColors.border)
            AppSectionHeader(title: "消耗统计")
            ForEach(stats.consumptionLines, id: \.output) { line in
                productionLineRow(line: line, color: AppColors.warning)
            }
        }
    }

    @ViewBuilder
    private var categories: some View {
        if !stats.categoryBreakdown.isEmpty {
            Divider().overlay(AppColors.border)
            AppSectionHeader(title: "建筑分类")
            ForEach(stats.categoryBreakdown.sorted(by: { $0.value > $1.value }), id: \.key) { category, count in
                HStack(alignment: .top, spacing: AppSpacing.sm) {
                    Image(systemName: category.icon).foregroundStyle(category.color).accessibilityHidden(true)
                    AppKeyValueRow(title: category.rawValue, value: "\(count)")
                }
            }
        }
    }

    private func powerText(_ stats: FactoryGridModel.ProductionStats) -> String {
        var parts: [String] = []
        if stats.hubPower > 0 { parts.append(String(format: "协议核心 %.0f", stats.hubPower)) }
        for generator in stats.generators {
            if let fuel = generator.fuel {
                parts.append(String(format: "热能池·%@ %.0f", fuel, generator.power))
            } else {
                parts.append("热能池·无燃料 0")
            }
        }
        let detail = parts.isEmpty ? "" : "（" + parts.joined(separator: " + ") + "）"
        return String(format: "耗电 %.1f MW，发电 %.1f MW", stats.totalPowerConsumed, stats.totalPowerGenerated) + detail
    }

    private func machineStateText(_ machine: FlowSimulator.MachineState) -> String {
        var text = "\(machine.name)：\(machine.status.label)"
        if machine.status != .noRecipe, machine.status != .inactive {
            text += "（\(Int((machine.throttle * 100).rounded()))%）"
        }
        if let detail = machine.detail { text += " · \(detail)" }
        return text
    }

    private func sinkText(_ sink: FlowSimulator.SinkState) -> String {
        let items = sink.consumed
            .filter { $0.value > 1e-9 }
            .sorted { $0.key < $1.key }
            .map { $0.key + " " + String(format: "%.1f", $0.value * 60) + "/min" }
        return "\(sink.name)：" + (items.isEmpty ? "无消耗" : items.joined(separator: "、"))
    }

    private func noticeRow(icon: String, text: String, itemNames: [String] = [], color: Color) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Label {
                Text(text).foregroundStyle(AppColors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: icon).foregroundStyle(color)
            }
            .font(AppTypography.supporting)
            if !itemNames.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: AppSpacing.xs) {
                        ForEach(itemNames, id: \.self) { name in ItemIcon(name: name, size: AppSize.icon) }
                    }
                }
            }
        }
        .padding(AppSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.elevatedSurface, in: RoundedRectangle(cornerRadius: AppRadius.control))
    }

    @ViewBuilder
    private func productionLineRow(line: FactoryGridModel.ProductionLine,
                                   color: Color = AppColors.success) -> some View {
        let row = HStack(alignment: .top, spacing: AppSpacing.sm) {
            ItemIcon(name: line.output, size: AppSize.itemIcon)
            AppKeyValueRow(title: line.output, value: String(format: "%.0f/min", line.ratePerMin))
            if onSelectItem != nil {
                Image(systemName: highlightedItem == line.output ? "scope" : "chevron.right")
                    .font(AppTypography.caption)
                    .foregroundStyle(highlightedItem == line.output ? AppColors.accent : AppColors.tertiaryText)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, AppSpacing.xs)
        .background(highlightedItem == line.output ? AppColors.accent.opacity(0.12) : .clear)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 2).offset(x: -AppSpacing.xs)
                .allowsHitTesting(false)
        }
        if let onSelectItem {
            Button { onSelectItem(line.output) } label: { row.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .accessibilityHint(highlightedItem == line.output ? "取消画布高亮" : "在画布上高亮相关机器和线")
        } else {
            row
        }
    }
}
