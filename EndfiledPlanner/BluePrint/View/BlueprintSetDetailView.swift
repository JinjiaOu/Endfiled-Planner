// Created by Jinjia Ou on 2/21/26.

import SwiftUI

struct BlueprintSetDetailView: View {
    let blueprintSet: BlueprintSet
    @Environment(\.dismiss) var dismiss
    @State private var copiedBlueprintId: String?

    var body: some View {
        NavigationStack {
            ZStack {
                AppTopographicBackground()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: AppSpacing.md) {
                        AppSurface {
                            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                                BlueprintLocation(region: blueprintSet.region, location: blueprintSet.location)
                                AppPageHeader(title: blueprintSet.name)
                                Label(String(localized: "作者：\(blueprintSet.author)"), systemImage: "person")
                                    .font(AppTypography.supporting).foregroundStyle(AppColors.secondaryText)
                                if !blueprintSet.description.isEmpty {
                                    Text(blueprintSet.description).font(AppTypography.body)
                                        .foregroundStyle(AppColors.primaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        AppSectionHeader(title: String(localized: "蓝图清单"), subtitle: String(localized: "共 \(blueprintSet.blueprints.count) 个 · 按原序号排列"))
                        ForEach(blueprintSet.blueprints.sorted(by: { $0.order < $1.order })) { blueprint in
                            BlueprintItemRow(blueprint: blueprint,
                                             isCopied: copiedBlueprintId == blueprint.id,
                                             onCopy: { copyToClipboard(blueprint.code, id: blueprint.id) })
                        }
                    }
                    .padding(AppSpacing.md)
                    .frame(maxWidth: 800, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(String(localized: "蓝图集详情"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "关闭")) { dismiss() }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(AppColors.background, for: .navigationBar)
            .tint(AppColors.accent)
        }
    }

    private func copyToClipboard(_ code: String, id: String) {
        UIPasteboard.general.string = code
        copiedBlueprintId = id
        
        // 1秒后重置
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            copiedBlueprintId = nil
        }
    }
}

struct BlueprintItemRow: View {
    let blueprint: BlueprintItem
    let isCopied: Bool
    let onCopy: () -> Void

    var body: some View {
        AppSurface {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                    Text(String(format: "%02d", blueprint.order)).font(AppTypography.numeric)
                        .foregroundStyle(AppColors.accent)
                    Text(blueprint.name).font(AppTypography.sectionTitle)
                        .foregroundStyle(AppColors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !blueprint.notes.isEmpty {
                    Text(blueprint.notes).font(AppTypography.supporting)
                        .foregroundStyle(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider().overlay(AppColors.border)
                Text(String(localized: "分享码")).font(AppTypography.caption).foregroundStyle(AppColors.secondaryText)
                Text(blueprint.code).font(AppTypography.code).foregroundStyle(AppColors.primaryText)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(AppSpacing.sm)
                    .background(AppColors.background, in: RoundedRectangle(cornerRadius: AppRadius.control))
                    .accessibilityLabel(String(localized: "蓝图分享码：\(blueprint.code)"))
                Button(action: onCopy) {
                    Label(isCopied ? String(localized: "已复制") : String(localized: "复制分享码"), systemImage: isCopied ? "checkmark" : "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(AppActionStyle(emphasis: .secondary))
                .accessibilityLabel(String(localized: "\(isCopied ? String(localized: "已复制") : String(localized: "复制分享码"))：\(blueprint.name)"))
            }
        }
    }
}

#Preview {
    BlueprintSetDetailView(blueprintSet: BlueprintSet(
        id: "set_001",
        name: "不用手拿植物——一键毕业省钱版",
        author: "示例UP主",
        region: "四号谷地",
        location: "枢纽区",
        description: "完整的自动化生产线系列",
        blueprints: [
            BlueprintItem(id: "bp_001", order: 1, name: "分基地全发电", code: "EF01081OupAE8706t79", notes: "一矿分基地+一基段"),
            BlueprintItem(id: "bp_002", order: 2, name: "分基地半发电", code: "EF010i5uiE49e55rruDeO", notes: "高级电池4.5")
        ]
    ))
}
