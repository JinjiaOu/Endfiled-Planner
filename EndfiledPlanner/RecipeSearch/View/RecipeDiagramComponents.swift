// Created by Jinjia Ou on 10/20/26.

import SwiftUI

/// 图形画布中的节点按画布比例缩放；完整动态字号信息另由依赖清单提供。
struct RecipeDiagramCard: View {
    let node: RecipeNode
    var compact = false

    private var tone: Color { node.recipe == nil ? AppColors.warning : AppColors.accent }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 2 : 5) {
            HStack(spacing: 5) {
                if !compact { ItemIcon(name: node.name, size: 20) }
                Text(verbatim: DisplayName.item(node.name)).font(.system(size: compact ? 9 : 14, weight: .semibold))
                    .lineLimit(2)
            }
            .foregroundStyle(AppColors.primaryText)
            Text("×\(node.amount)")
                .font(.system(size: compact ? 8 : 12, weight: .medium, design: .monospaced))
                .foregroundStyle(AppColors.secondaryText)
            if !compact, let recipe = node.recipe {
                Text(verbatim: recipe.displayMachine).font(.system(size: 10)).foregroundStyle(AppColors.secondaryText).lineLimit(1)
                if recipe.time > 0 && !RecipeViewModel.isMiningMachine(recipe.machine) {
                    Text("\(recipe.time)s").font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(AppColors.secondaryText)
                }
            }
        }
        .padding(compact ? 5 : 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(AppColors.surface)
        .overlay { Rectangle().strokeBorder(AppColors.controlBorder, lineWidth: compact ? 0.7 : 1) }
        .overlay(alignment: .leading) { Rectangle().fill(tone).frame(width: compact ? 1 : 3) }
        .accessibilityElement(children: .combine)
    }
}

/// 只遍历现有树；不重新计算节点、产量、批次或耗时。
struct RecipeDependencyOutline: View {
    let node: RecipeNode
    var depth = 0

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            AppSurface {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(depth == 0 ? String(localized: "目标物品") : String(localized: "依赖层级 \(depth)"))
                        .font(AppTypography.caption).foregroundStyle(AppColors.secondaryText)
                    HStack(alignment: .top, spacing: AppSpacing.sm) {
                        ItemIcon(name: node.name, size: AppSize.itemIcon)
                        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                            Text(verbatim: DisplayName.item(node.name)).font(AppTypography.rowTitle).foregroundStyle(AppColors.primaryText)
                            Text(String(localized: "数量 \(node.amount)")).font(AppTypography.numeric).foregroundStyle(AppColors.secondaryText)
                        }
                    }
                    if let recipe = node.recipe {
                        Text(verbatim: recipe.displayMachine).font(AppTypography.supporting).foregroundStyle(AppColors.secondaryText)
                        if recipe.time > 0 && !RecipeViewModel.isMiningMachine(recipe.machine) {
                            Label(String(localized: "\(recipe.time) 秒"), systemImage: "clock")
                                .font(AppTypography.supporting).foregroundStyle(AppColors.secondaryText)
                        }
                    } else {
                        Text(String(localized: "原材料")).font(AppTypography.caption).foregroundStyle(AppColors.warning)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(min(depth, 4)) * AppSpacing.xs)
            ForEach(node.children) { child in
                RecipeDependencyOutline(node: child, depth: depth + 1)
            }
        }
    }
}
