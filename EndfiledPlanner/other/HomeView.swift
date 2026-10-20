// Created by Jinjia Ou on 10/19/26.

import SwiftUI

/// 首页统一提供三个功能入口、数据概览和设置。
struct HomeView: View {
    var onOpenSection: (AppSection) -> Void
    @ObservedObject private var dataUpdater = DataPackUpdater.shared
    @State private var showsSettings = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                AppPageHeader(title: "终末地生产规划", subtitle: "查配方、找蓝图、规划产线。")

                if dataUpdater.showsHomeBanner {
                    DataUpdateBanner()
                }

                taskList
                HomeDatabaseSummary()
            }
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.md)
            .frame(maxWidth: 1040, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("工作台")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showsSettings = true } label: {
                    Image(systemName: "gearshape")
                        .overlay(alignment: .topTrailing) {
                            if dataUpdater.hasUpdate {
                                Circle().fill(AppColors.error)
                                    .frame(width: 7, height: 7)
                                    .offset(x: 3, y: -3)
                            }
                        }
                }
                .accessibilityLabel(dataUpdater.hasUpdate ? "设置，有新数据可下载" : "设置")
            }
        }
        .appPageStyle(topographicBackground: true)
        .sheet(isPresented: $showsSettings) {
            SettingsView(isPresentedModally: true)
        }
    }

    private var taskList: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            AppSectionHeader(title: "开始规划")
            taskRow("基建规划", subtitle: "编辑布局、连接产线、查看运行状态",
                    symbol: "building.2", destination: .factory)
            taskRow("配方分析", subtitle: "搜索物品，展开完整生产依赖",
                    symbol: "doc.text.magnifyingglass", destination: .recipes)
            taskRow("社区蓝图", subtitle: "按作者和地图查找，复制蓝图码",
                    symbol: "square.stack", destination: .blueprints)
        }
    }

    private func taskRow(_ title: String, subtitle: String, symbol: String, destination: AppSection) -> some View {
        Button { onOpenSection(destination) } label: {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: symbol).font(.title3.weight(.medium))
                    .foregroundStyle(AppColors.accent)
                    .frame(width: AppSize.itemIcon)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text(title).font(AppTypography.sectionTitle).foregroundStyle(AppColors.primaryText)
                    Text(subtitle).font(AppTypography.supporting).foregroundStyle(AppColors.secondaryText)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(AppTypography.caption)
                    .foregroundStyle(AppColors.tertiaryText).accessibilityHidden(true)
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.lg)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
            .background(AppColors.surface, in: RoundedRectangle(cornerRadius: AppRadius.surface))
            .overlay(alignment: .topTrailing) {
                HomeCardCornerDots()
                    .frame(width: 64, height: 32)
                    .padding(AppSpacing.xs)
            }
            .overlay(alignment: .bottomLeading) {
                HomeCardCornerDots()
                    .frame(width: 40, height: 18)
                    .rotationEffect(.degrees(180))
                    .padding(AppSpacing.xs)
            }
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.surface))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.surface)
                    .strokeBorder(AppColors.border, lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }

}

/// 仅限卡片角落的渐疏波点，不遮挡点击，也不进入辅助功能树。
private struct HomeCardCornerDots: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 7
            let columns = Int(size.width / spacing)
            let rows = Int(size.height / spacing)
            for row in 0..<rows {
                for column in row..<columns {
                    let diameter: CGFloat = 1.7
                    let dot = CGRect(x: size.width - CGFloat(column - row + 1) * spacing,
                                     y: CGFloat(row) * spacing,
                                     width: diameter, height: diameter)
                    let opacity = 0.42 - Double(column) * 0.035
                    context.fill(Path(ellipseIn: dot), with: .color(AppColors.controlBorder.opacity(opacity)))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct HomeDatabaseSummary: View {
    @StateObject private var vm = RecipeViewModel()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    // 保留原首页按产物分组求和、以机器显示名去重的计数方式。
    private var recipeCount: Int { vm.recipes.values.reduce(0) { $0 + $1.count } }
    private var machineCount: Int { Set(vm.recipes.values.flatMap { $0.map(\.machine) }).count }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            AppSectionHeader(title: "数据概览")
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                if dynamicTypeSize.isAccessibilitySize {
                    AppKeyValueRow(title: "配方", value: "\(recipeCount)")
                    AppKeyValueRow(title: "产物", value: "\(vm.recipes.keys.count)")
                    AppKeyValueRow(title: "设备", value: "\(machineCount)")
                } else {
                    HStack(alignment: .top, spacing: AppSpacing.md) {
                        AppMetricCell(title: "配方", value: "\(recipeCount)")
                        AppMetricCell(title: "产物", value: "\(vm.recipes.keys.count)")
                        AppMetricCell(title: "设备", value: "\(machineCount)")
                    }
                }
                Text("配方按产物分组统计，多产物配方会分别计入。")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(AppSpacing.md)
            .background(AppColors.surface, in: RoundedRectangle(cornerRadius: AppRadius.surface))
        }
    }
}
