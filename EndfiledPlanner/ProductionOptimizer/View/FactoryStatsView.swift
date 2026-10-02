//
//  FactoryStatsView.swift
//  EndfiledPlanner
//
//  Created by Jinjia Ou on 4/3/26.
//

import SwiftUI

struct FactoryStatsView: View {

    let stats: FactoryGridModel.ProductionStats
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(spacing: 0) {

            // 折叠标题栏
            Button {
                withAnimation(.spring(response: 0.3)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Rectangle()
                        .fill(Color(red: 0.4, green: 0.8, blue: 0.2))
                        .frame(width: 3, height: 14)

                    Text("产能统计")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.9))

                    Spacer()

                    // 电力余量快速预览（发电－耗电，正数=有富余，负数=不够）
                    Text(String(format: "%+.1f MW", powerMargin))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(powerMarginColor)

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.leading, 6)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(red: 0.08, green: 0.09, blue: 0.12))
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 0) {

                    // 总览数据行
                    HStack(spacing: 0) {
                        statBox(
                            title: "建筑",
                            value: "\(stats.buildingCount)",
                            unit: "总数",
                            color: Color(red: 1.0, green: 0.8, blue: 0.0)
                        )
                        Divider().overlay(Color.white.opacity(0.1))
                        statBox(
                            title: "总发电量",
                            value: String(format: "%.0f", stats.totalPowerGenerated),
                            unit: "MW",
                            color: Color(red: 1.0, green: 0.8, blue: 0.0)
                        )
                        Divider().overlay(Color.white.opacity(0.1))
                        statBox(
                            title: "用电量",
                            value: String(format: "%.0f", stats.totalPowerConsumed),
                            unit: "MW",
                            color: powerMarginColor
                        )
                        Divider().overlay(Color.white.opacity(0.1))
                        statBox(
                            title: "产线",
                            value: "\(stats.productionLines.count)",
                            unit: "条",
                            color: Color(red: 0.4, green: 0.8, blue: 0.2)
                        )
                    }
                    .frame(height: 64)
                    .background(Color(red: 0.12, green: 0.13, blue: 0.16))

                    // 瓶颈提示
                    if let bottleneck = stats.bottleneck {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(Color(red: 0.9, green: 0.5, blue: 0.2))
                            Text("瓶颈：\(bottleneck)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(red: 0.9, green: 0.5, blue: 0.2))
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color(red: 0.9, green: 0.5, blue: 0.2).opacity(0.1))
                    }

                    // 直通节点提示（分流器/汇流器/物流桥等，不产不耗，不算进下面的产线）
                    if stats.passthroughCount > 0 {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 11))
                                .foregroundColor(Color(red: 0.4, green: 0.7, blue: 0.9))
                            Text("直通节点 ×\(stats.passthroughCount)（分流器/汇流器等，不计入产线）")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(red: 0.4, green: 0.7, blue: 0.9))
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color(red: 0.4, green: 0.7, blue: 0.9).opacity(0.1))
                    }

                    // 仓库取线：没有速率概念（游戏里取多少取决于仓库存量），只列出每个出口设置了什么
                    if !stats.outletMaterials.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "shippingbox.fill")
                                .font(.system(size: 11))
                                .foregroundColor(Color(red: 0.4, green: 0.8, blue: 0.2))
                            Text("仓库取线：\(stats.outletMaterials.joined(separator: "、"))")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(red: 0.4, green: 0.8, blue: 0.2))
                                .lineLimit(2)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color(red: 0.4, green: 0.8, blue: 0.2).opacity(0.1))
                    }

                    // 电力：耗电 / 发电分项（发电 = 协议核心 + 各热能池按燃料算）
                    if stats.totalPowerGenerated > 0 || stats.totalPowerConsumed > 0 {
                        noticeRow(icon: "bolt.horizontal.fill",
                                  text: powerText(stats),
                                  color: Color(red: 1.0, green: 0.8, blue: 0.0))
                    }
                    if stats.powerShortage > 1e-6 {
                        noticeRow(icon: "bolt.slash.fill",
                                  text: String(format: "电力不足：还差 %.1f MW", stats.powerShortage),
                                  color: Color(red: 0.9, green: 0.3, blue: 0.2))
                    }
                    if stats.unpoweredCount > 0 {
                        noticeRow(icon: "powerplug",
                                  text: "未通电 ×\(stats.unpoweredCount)（不在供电桩范围内，不运行）",
                                  color: Color(red: 0.9, green: 0.3, blue: 0.2))
                    }

                    // 流量模拟没收敛：数字仅供参考
                    if !stats.flowConverged {
                        noticeRow(icon: "exclamationmark.triangle.fill",
                                  text: "流量模拟未收敛（可能有环路），数字仅供参考",
                                  color: Color(red: 0.9, green: 0.3, blue: 0.2))
                    }

                    // 没正常运行的机器
                    ForEach(stats.machineStates.filter { $0.status != .running }) { machine in
                        noticeRow(icon: "gearshape.fill",
                                  text: machineStateText(machine),
                                  color: Color(red: 0.9, green: 0.5, blue: 0.2))
                    }

                    // 终点消耗（存货口/废水处理机实际吃进去的东西）
                    ForEach(stats.sinkStates) { sink in
                        noticeRow(icon: "tray.and.arrow.down.fill",
                                  text: sinkText(sink),
                                  itemNames: sink.consumed.filter { $0.value > 1e-9 }.map(\.key).sorted(),
                                  color: Color(red: 0.4, green: 0.7, blue: 0.9))
                    }

                    // 建筑类型分布
                    if !stats.categoryBreakdown.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("建筑分类")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.4))
                                .padding(.horizontal, 14)
                                .padding(.top, 10)

                            ForEach(stats.categoryBreakdown.sorted(by: { $0.value > $1.value }), id: \.key) { category, count in
                                categoryRow(category: category, count: count)
                            }
                        }
                        .padding(.bottom, 10)
                        .background(Color(red: 0.12, green: 0.13, blue: 0.16))
                    }

                    // 产线列表
                    if !stats.productionLines.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack {
                                Rectangle()
                                    .fill(Color(red: 0.4, green: 0.8, blue: 0.2))
                                    .frame(width: 3, height: 12)

                                Text("产出产线")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.6))

                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color(red: 0.08, green: 0.09, blue: 0.12))

                            ForEach(stats.productionLines, id: \.output) { line in
                                productionLineRow(line: line)
                            }
                        }
                    }

                    // 消耗列表
                    if !stats.consumptionLines.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack {
                                Rectangle()
                                    .fill(Color(red: 0.9, green: 0.5, blue: 0.2))
                                    .frame(width: 3, height: 12)

                                Text("消耗统计")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.6))

                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color(red: 0.08, green: 0.09, blue: 0.12))

                            ForEach(stats.consumptionLines, id: \.output) { line in
                                productionLineRow(line: line, color: Color(red: 0.9, green: 0.5, blue: 0.2))
                            }
                        }
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(
            Rectangle()
                .stroke(Color(red: 0.4, green: 0.8, blue: 0.2).opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - 子组件

    /// 发电 − 耗电：正数表示还有富余，负数表示电不够
    private var powerMargin: Double { stats.totalPowerGenerated - stats.totalPowerConsumed }
    private var powerMarginColor: Color {
        powerMargin >= 0 ? Color(red: 0.4, green: 0.8, blue: 0.2) : Color(red: 0.9, green: 0.3, blue: 0.2)
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

    private func noticeRow(icon: String, text: String, itemNames: [String] = [], color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(color)
            ForEach(itemNames, id: \.self) { name in
                ItemIcon(name: name, size: 20)
            }
            Text(text)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(color)
                .lineLimit(3)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
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

    private func statBox(title: String, value: String, unit: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundColor(color)
            Text(unit)
                .font(.system(size: 7, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
    }

    private func categoryRow(category: BuildingCategory, count: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: category.icon)
                .font(.system(size: 11))
                .foregroundColor(category.color)
                .frame(width: 18)

            Text(category.rawValue)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.7))

            Spacer()

            Text("\(count)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(category.color)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
    }

    private func productionLineRow(line: FactoryGridModel.ProductionLine,
                                   color: Color = Color(red: 0.4, green: 0.8, blue: 0.2)) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color.opacity(0.6))
                .frame(width: 6, height: 6)

            ItemIcon(name: line.output, size: 24)

            Text(line.output)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.8))

            Spacer()

            Text(String(format: "%.0f/min", line.ratePerMin))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(color)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color(red: 0.12, green: 0.13, blue: 0.16))
    }
}
