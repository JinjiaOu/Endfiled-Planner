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

                    // 总功率快速预览
                    Text(String(format: "%.1f MW", stats.totalPower))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(red: 0.9, green: 0.5, blue: 0.2))

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
                            title: "功率",
                            value: String(format: "%.1f", stats.totalPower),
                            unit: "MW",
                            color: Color(red: 0.9, green: 0.5, blue: 0.2)
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

    private func productionLineRow(line: FactoryGridModel.ProductionLine) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(red: 0.4, green: 0.8, blue: 0.2).opacity(0.6))
                .frame(width: 6, height: 6)

            Text(line.output)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.8))

            Spacer()

            Text(String(format: "%.0f/min", line.ratePerMin))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(Color(red: 0.4, green: 0.8, blue: 0.2))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color(red: 0.12, green: 0.13, blue: 0.16))
    }
}
