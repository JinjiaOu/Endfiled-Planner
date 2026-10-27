// Created by Jinjia Ou on 10/21/26.

import SwiftUI

/// 首页独立入口：选产物 + 目标产量，反推每级机器台数、原料、副产物和耗电
struct ProductionCalculatorView: View {
    @StateObject private var recipeVM = RecipeViewModel()
    @AppStorage("calculatorTarget") private var target = ""
    @AppStorage("calculatorRate") private var rate = 6.0
    /// 用户手动换的配方 / 手动指定当原料或展开；换目标产物时清空
    @State private var recipeChoice: [String: String] = [:]
    @State private var rawOverride: [String: Bool] = [:]
    @State private var showTargetPicker = false
    @State private var recipeSheetItem: CalculatorItem?
    @FocusState private var rateFocused: Bool

    private var result: ProductionCalculator.Result? {
        guard !target.isEmpty, !recipeVM.recipes.isEmpty, rate > 0 else { return nil }
        return ProductionCalculator.calculate(target: target, ratePerMin: rate, recipes: recipeVM.recipes,
                                              recipeChoice: recipeChoice, rawOverride: rawOverride)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                AppPageHeader(title: String(localized: "产量计算"), subtitle: String(localized: "选产物和目标产量，反推每一级要几台机器、多少原料和电。"))
                targetCard
                if let result {
                    summary(result)
                    stepsSection(result)
                    rawsSection(result)
                    byproductsSection(result)
                    notes(result)
                } else {
                    AppSurface {
                        AppContentState(title: String(localized: "先选一个产物"), message: String(localized: "点上面的“选择产物”，再填每分钟要多少个。"),
                                        systemImage: "function")
                    }
                }
            }
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.md)
            .frame(maxWidth: 1040, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(String(localized: "产量计算"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(String(localized: "完成")) { rateFocused = false }
            }
        }
        .appPageStyle()
        .sheet(isPresented: $showTargetPicker) {
            SearchablePickerSheet(
                title: String(localized: "选择产物"),
                items: productItems,
                selectedID: target.isEmpty ? nil : target,
                onSelect: { picked in
                    guard let picked, picked != target else { return }
                    target = picked
                    recipeChoice = [:]
                    rawOverride = [:]
                }
            )
        }
        .sheet(item: $recipeSheetItem) { entry in
            let list = ProductionCalculator.candidates(for: entry.item, in: recipeVM.recipes)
            let current = result?.steps.first { $0.item == entry.item }?.recipe.id
            SearchablePickerSheet(
                title: String(localized: "\(DisplayName.item(entry.item)) 用哪条配方"),
                items: list.map { recipe in
                    SearchablePickerItem(id: recipe.id, title: recipe.displayMachine,
                                         subtitle: recipeSummary(recipe), iconName: entry.item,
                                         searchTerms: recipe.machine + " " + (recipe.inputs + recipe.outputs).map(\.name).joined(separator: " "))
                },
                selectedID: current,
                onSelect: { id in
                    if let id { recipeChoice[entry.item] = id }
                }
            )
        }
    }

    // MARK: - 目标

    private var productItems: [SearchablePickerItem] {
        recipeVM.recipes.keys
            .filter { !ProductionCalculator.candidates(for: $0, in: recipeVM.recipes).isEmpty }
            .sorted()
            .map { SearchablePickerItem(id: $0, title: DisplayName.item($0), iconName: $0) }
    }

    private var targetCard: some View {
        AppSurface {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Button { showTargetPicker = true } label: {
                    HStack(spacing: AppSpacing.sm) {
                        if target.isEmpty {
                            Image(systemName: "shippingbox").font(.title3)
                                .foregroundStyle(AppColors.accent)
                                .frame(width: AppSize.itemIcon, height: AppSize.itemIcon)
                        } else {
                            ItemIcon(name: target, size: AppSize.itemIcon)
                        }
                        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                            Text(String(localized: "目标产物")).font(AppTypography.caption).foregroundStyle(AppColors.secondaryText)
                            Text(verbatim: target.isEmpty ? String(localized: "选择产物") : DisplayName.item(target))
                                .font(AppTypography.sectionTitle).foregroundStyle(AppColors.primaryText)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(AppTypography.caption)
                            .foregroundStyle(AppColors.tertiaryText)
                    }
                    .frame(minHeight: AppSize.touchTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Divider().overlay(AppColors.border)

                HStack(spacing: AppSpacing.sm) {
                    Text(String(localized: "目标产量")).font(AppTypography.rowTitle).foregroundStyle(AppColors.primaryText)
                    Spacer()
                    TextField(String(localized: "每分钟"), value: $rate, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(AppTypography.numeric)
                        .focused($rateFocused)
                        .frame(maxWidth: 120)
                        .padding(.horizontal, AppSpacing.xs)
                        .frame(minHeight: AppSize.touchTarget)
                        .background(AppColors.background, in: RoundedRectangle(cornerRadius: AppRadius.control))
                        .accessibilityLabel(String(localized: "目标产量，每分钟个数"))
                    Text(String(localized: "个/分钟")).font(AppTypography.supporting).foregroundStyle(AppColors.secondaryText)
                }
                HStack(spacing: AppSpacing.xs) {
                    ForEach([1.0, 6.0, 30.0, 60.0], id: \.self) { preset in
                        Button("\(Self.format(preset))") { rate = preset; rateFocused = false }
                            .buttonStyle(AppActionStyle(emphasis: rate == preset ? .primary : .secondary))
                    }
                }
            }
        }
    }

    // MARK: - 结果

    private func summary(_ result: ProductionCalculator.Result) -> some View {
        AppMetricGrid {
            AppMetricCell(title: String(localized: "机器"), value: "\(result.totalMachines)", unit: String(localized: "台（按整台算）"))
            AppMetricCell(title: String(localized: "耗电"), value: Self.format(result.powerMW), unit: String(localized: "MW（满台数估算）"))
            AppMetricCell(title: String(localized: "生产步骤"), value: "\(result.steps.count)", unit: String(localized: "种物品"))
        }
    }

    @ViewBuilder
    private func stepsSection(_ result: ProductionCalculator.Result) -> some View {
        if !result.steps.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                AppSectionHeader(title: String(localized: "生产步骤"), subtitle: String(localized: "从成品往上游排；点右边的按钮换配方或改成从仓库取"))
                VStack(spacing: 0) {
                    ForEach(result.steps) { step in
                        stepRow(step)
                        if step.id != result.steps.last?.id { Divider().overlay(AppColors.border) }
                    }
                }
                .background(AppColors.surface, in: RoundedRectangle(cornerRadius: AppRadius.surface))
            }
        }
    }

    private func stepRow(_ step: ProductionCalculator.Step) -> some View {
        HStack(alignment: .center, spacing: AppSpacing.sm) {
            ItemIcon(name: step.item, size: AppSize.itemIcon)
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(verbatim: DisplayName.item(step.item)).font(AppTypography.rowTitle).foregroundStyle(AppColors.primaryText)
                Text("\(step.recipe.displayMachine) × \(step.machineCount)")
                    .font(AppTypography.supporting).foregroundStyle(AppColors.accent)
                Text(String(localized: "精确 \(String(format: "%.2f", step.machines)) 台 · 每台 \(step.recipe.time) 秒一次"))
                    .font(AppTypography.caption).foregroundStyle(AppColors.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(String(localized: "\(Self.format(step.ratePerMin))/分"))
                .font(AppTypography.numeric).foregroundStyle(AppColors.primaryText)
            Menu {
                if step.recipeChoices > 1 {
                    Button { recipeSheetItem = CalculatorItem(item: step.item) } label: {
                        Label(String(localized: "换配方（\(step.recipeChoices) 条可选）"), systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                if step.item != target {
                    Button { rawOverride[step.item] = true } label: {
                        Label(String(localized: "改成从仓库取，不再展开"), systemImage: "shippingbox")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle").foregroundStyle(AppColors.secondaryText)
                    .frame(width: AppSize.touchTarget, height: AppSize.touchTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(String(localized: "\(DisplayName.item(step.item)) 的选项"))
        }
        .padding(.leading, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
    }

    @ViewBuilder
    private func rawsSection(_ result: ProductionCalculator.Result) -> some View {
        if !result.raws.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                AppSectionHeader(title: String(localized: "原料"), subtitle: String(localized: "从仓库取或外部供给，不再往上游展开"))
                VStack(spacing: 0) {
                    ForEach(result.raws, id: \.item) { raw in
                        rawRow(raw.item, rate: raw.ratePerMin, isCycle: result.cycleBreaks.contains(raw.item))
                        if raw.item != result.raws.last?.item { Divider().overlay(AppColors.border) }
                    }
                }
                .background(AppColors.surface, in: RoundedRectangle(cornerRadius: AppRadius.surface))
            }
        }
    }

    private func rawRow(_ item: String, rate: Double, isCycle: Bool) -> some View {
        let canExpand = !ProductionCalculator.candidates(for: item, in: recipeVM.recipes).isEmpty && !isCycle
        return HStack(spacing: AppSpacing.sm) {
            ItemIcon(name: item, size: AppSize.itemIcon)
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(verbatim: DisplayName.item(item)).font(AppTypography.rowTitle).foregroundStyle(AppColors.primaryText)
                Text(isCycle ? String(localized: "循环依赖，这一截按原料算") : lineHint(item, rate: rate))
                    .font(AppTypography.caption)
                    .foregroundStyle(isCycle ? AppColors.warning : AppColors.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(String(localized: "\(Self.format(rate))/分")).font(AppTypography.numeric).foregroundStyle(AppColors.primaryText)
            if canExpand {
                Menu {
                    Button { rawOverride[item] = false } label: {
                        Label(String(localized: "展开生产"), systemImage: "arrow.down.right.and.arrow.up.left")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").foregroundStyle(AppColors.secondaryText)
                        .frame(width: AppSize.touchTarget, height: AppSize.touchTarget)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(String(localized: "\(DisplayName.item(item)) 的选项"))
            } else {
                Color.clear.frame(width: AppSize.touchTarget, height: 1)
            }
        }
        .padding(.leading, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
    }

    @ViewBuilder
    private func byproductsSection(_ result: ProductionCalculator.Result) -> some View {
        if !result.byproducts.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                AppSectionHeader(title: String(localized: "副产物"), subtitle: String(localized: "多产物配方顺带产出的，要另外处理（存仓库或接废水处理机）"))
                VStack(spacing: 0) {
                    ForEach(result.byproducts, id: \.item) { by in
                        HStack(spacing: AppSpacing.sm) {
                            ItemIcon(name: by.item, size: AppSize.itemIcon)
                            Text(verbatim: DisplayName.item(by.item)).font(AppTypography.rowTitle).foregroundStyle(AppColors.primaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(String(localized: "\(Self.format(by.ratePerMin))/分")).font(AppTypography.numeric)
                                .foregroundStyle(AppColors.primaryText)
                        }
                        .padding(AppSpacing.sm)
                        if by.item != result.byproducts.last?.item { Divider().overlay(AppColors.border) }
                    }
                }
                .background(AppColors.surface, in: RoundedRectangle(cornerRadius: AppRadius.surface))
            }
        }
    }

    private func notes(_ result: ProductionCalculator.Result) -> some View {
        AppInlineNotice(
            title: String(localized: "计算说明"),
            message: String(localized: "按稳定满速算，同一物品在多条分支里的需求已合并；副产物不会自动抵扣需求；")
                + String(localized: "耗电按取整后的台数估算。矿石默认从仓库取，水和气默认算成水泵、气泵。"),
            tone: .neutral
        )
    }

    // MARK: - 工具

    /// 原料大概要几条线：固体按传送带、液体气体按管道的上限算
    private func lineHint(_ item: String, rate: Double) -> String {
        let solid = ItemCatalog.byName[item]?.phase == .solid
        let cap = (solid ? FlowSimulator.beltCapacity : FlowSimulator.pipeCapacity) * 60
        let lines = Int((rate / cap - 1e-9).rounded(.up))
        return String(localized: "约 \(max(lines, 1)) 条\(solid ? String(localized: "传送带") : String(localized: "管道"))")
    }

    private func recipeSummary(_ recipe: Recipe) -> String {
        let ins = recipe.inputs.map { "\(DisplayName.item($0.name))×\($0.count)" }.joined(separator: "、")
        let outs = recipe.outputs.map { "\(DisplayName.item($0.name))×\($0.count)" }.joined(separator: "、")
        return String(localized: "\(ins.isEmpty ? String(localized: "无原料") : ins) → \(outs) · \(recipe.time) 秒")
    }

    static func format(_ value: Double) -> String {
        if abs(value - value.rounded()) < 1e-6 { return String(format: "%.0f", value) }
        return value >= 10 ? String(format: "%.1f", value) : String(format: "%.2f", value)
    }
}

/// sheet(item:) 用的包装
private struct CalculatorItem: Identifiable {
    let item: String
    var id: String { item }
}

#Preview {
    NavigationStack { ProductionCalculatorView() }
}
