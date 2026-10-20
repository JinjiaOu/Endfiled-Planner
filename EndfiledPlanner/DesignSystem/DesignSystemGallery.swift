// Created by Jinjia Ou on 10/19/26.

import SwiftUI

/// Xcode Preview 的组件目录，不接入 App 导航，不读取或写入用户数据。
/// 示例数值仅用于排版展示，不是 FlowSimulator 的运行结果。
struct DesignSystemGallery: View {
    @State private var query = ""
    @State private var selectedTool = "选择"
    @State private var filterSelected = true
    @State private var selectedMaterial = true
    @State private var restrictedSelection = true
    @State private var inspectorExpanded = true
    @State private var showsInspector = true
    @State private var showsFeedback = false
    @State private var showsError = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.xl) {
                    AppPageHeader(title: "工业终端 · 组件目录", subtitle: "Phase 2 · 以下均为独立的界面示例")
                    colorSection
                    actionSection
                    selectionSection
                    metricSection
                    statusSection
                    inspectorSection
                }
                .padding(AppSpacing.md)
            }
            .navigationTitle("设计系统")
            .navigationBarTitleDisplayMode(.inline)
            .appPageStyle()
        }
    }

    private var colorSection: some View {
        AppSurface {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                AppSectionHeader(title: "表面与文字", subtitle: "系统中文字体 · 等宽数字 · 工业黄强调")
                Text("主要信息使用清晰的中性色，强调色仅提示操作与选择。")
                    .font(AppTypography.body).foregroundStyle(AppColors.primaryText)
                Text("辅助说明保留完整内容，随系统字号换行。")
                    .font(AppTypography.supporting).foregroundStyle(AppColors.secondaryText)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: AppSize.touchTarget))], spacing: AppSpacing.xs) {
                    swatch("强调", color: AppColors.accentFill)
                    swatch("成功", color: AppColors.success)
                    swatch("警告", color: AppColors.warning)
                    swatch("错误", color: AppColors.error)
                    swatch("信息", color: AppColors.info)
                }
            }
        }
    }

    private func swatch(_ title: String, color: Color) -> some View {
        VStack(spacing: AppSpacing.xs) {
            RoundedRectangle(cornerRadius: AppRadius.control)
                .fill(color).frame(height: AppSize.icon).accessibilityHidden(true)
            Text(title).font(AppTypography.caption).foregroundStyle(AppColors.secondaryText)
        }
    }

    private var actionSection: some View {
        AppSurface {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                AppSectionHeader(title: "动作与工具", subtitle: "点击示例动作可查看局部反馈")
                Button("显示成功反馈") { showsFeedback.toggle() }.buttonStyle(AppActionStyle())
                Button("隐藏反馈") { showsFeedback = false }
                    .buttonStyle(AppActionStyle(emphasis: .secondary))
                Button("不可用操作") { showsFeedback = true }
                    .buttonStyle(AppActionStyle()).disabled(true)
                if showsFeedback { AppFeedbackToast(title: "操作完成（展示示例）") }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: AppSize.touchTarget * 2))], spacing: AppSpacing.xs) {
                    tool("选择", symbol: "cursorarrow")
                    tool("建造", symbol: "plus.square")
                    tool("传送带", symbol: "arrow.left.and.right")
                    tool("框选", symbol: "rectangle.dashed")
                }
            }
        }
    }

    private func tool(_ title: String, symbol: String) -> some View {
        AppToolButton(title: title, systemImage: symbol, isSelected: selectedTool == title) { selectedTool = title }
    }

    private var selectionSection: some View {
        AppSurface {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                AppSectionHeader(title: "搜索与选择")
                AppSearchField(text: $query, prompt: "输入关键词查看输入样式")
                AppFilterChip(title: "原料筛选", isSelected: filterSelected) { filterSelected.toggle() }
                AppSelectionRow(title: "高容谷地电池", subtitle: "原料与产物说明可完整换行",
                                isSelected: selectedMaterial, multiSelect: true,
                                action: { selectedMaterial.toggle() }) {
                    Image(systemName: "cube.fill").foregroundStyle(AppColors.info)
                }
                AppSelectionRow(title: "已选择的受限配方", subtitle: "保留已选项的取消入口",
                                isSelected: restrictedSelection, multiSelect: true, restriction: "仅武陵",
                                isSelectable: restrictedSelection, hint: "可取消选择",
                                action: { restrictedSelection = false }) {
                    Image(systemName: "drop.fill").foregroundStyle(AppColors.info)
                }
                if !restrictedSelection {
                    Button("重置选择示例") { restrictedSelection = true }
                        .buttonStyle(AppActionStyle(emphasis: .secondary))
                }
            }
        }
    }

    private var metricSection: some View {
        AppSurface {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                AppSectionHeader(title: "指标与明细", subtitle: "示例数值，仅展示排版；不连接模拟器")
                AppMetricGrid {
                    AppMetricCell(title: "电力余量", value: "+20.0", unit: "MW", tone: .success)
                    AppMetricCell(title: "实际产出", value: "6.0", unit: "个/分钟")
                }
                Divider().overlay(AppColors.border)
                AppKeyValueRow(title: "到货 / 需求", value: "12.0 / 24.0 个/分钟", detail: "长物品名及单位应完整显示")
            }
        }
    }

    private var statusSection: some View {
        AppSurface {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                AppSectionHeader(title: "状态与反馈")
                AppStatusBadge(title: "生产中", tone: .success)
                AppInlineNotice(title: "原料不足", message: "查看到货量与需求量，检查上游连接。", tone: .warning)
                AppLoadingState(title: "正在下载游戏数据", progress: 0.4, detail: "展示进度 40%")
                if showsError {
                    AppContentState(title: "加载失败", message: "此处为错误状态示例，重试按钮仅切换预览状态。",
                                    systemImage: "wifi.exclamationmark", tone: .error) {
                        Button("重试示例") { showsError = false }.buttonStyle(AppActionStyle(emphasis: .secondary))
                    }
                } else {
                    AppContentState(title: "暂无布局", message: "在画布中框选建筑后，可以存为我的布局。")
                    Button("显示错误示例") { showsError = true }.buttonStyle(AppActionStyle(emphasis: .secondary))
                }
            }
        }
    }

    @ViewBuilder
    private var inspectorSection: some View {
        if showsInspector {
            AppInspectorContainer(title: "建筑检查面板", subtitle: "非模态容器示例",
                                  isExpanded: $inspectorExpanded, maxContentHeight: AppSize.metricColumnMinimum * 2,
                                  onClose: { showsInspector = false }) {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    AppStatusBadge(title: "原料不足", tone: .warning)
                    AppKeyValueRow(title: "实际运行率", value: "50%")
                    AppInlineNotice(title: "内容区域可滚动", message: "外层页面负责可用高度和位置。")
                }
            } actions: {
                Button("折叠 / 展开内容") { inspectorExpanded.toggle() }
                    .buttonStyle(AppActionStyle(emphasis: .secondary))
            }
        } else {
            Button("显示检查面板示例") { showsInspector = true }
                .buttonStyle(AppActionStyle(emphasis: .secondary))
        }
    }
}

#Preview("深色 · 组件目录") {
    DesignSystemGallery().preferredColorScheme(.dark)
}

#Preview("浅色 · 组件目录") {
    DesignSystemGallery().preferredColorScheme(.light)
}

#Preview("大字 · 组件目录") {
    DesignSystemGallery().preferredColorScheme(.dark).dynamicTypeSize(.accessibility5)
}
