// Created by Jinjia Ou on 10/19/26.

import SwiftUI

/// 非模态检查器：手机摘要可展开，宽屏完整配置独立滚动。
struct AppInspectorContainer<Content: View, Actions: View>: View {
    enum Placement: Equatable { case bottom, side }

    let title: String
    var subtitle: String? = nil
    var placement: Placement = .bottom
    @Binding var isExpanded: Bool
    var maxContentHeight: CGFloat? = nil
    var maxPanelHeight: CGFloat? = nil
    var summaryText: String? = nil
    var disclosureTitle: String = String(localized: "详细配置")
    var onClose: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content
    @ViewBuilder var actions: () -> Actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var showsDetails: Bool { placement == .side || isExpanded }

    // 窄横屏或辅助字号下，让标题与动作一起滚动，避免它们挤出可见边界。
    private var needsFullScroll: Bool {
        guard let maxPanelHeight else { return false }
        return dynamicTypeSize.isAccessibilitySize || maxPanelHeight < 240
    }

    var body: some View {
        Group {
            if needsFullScroll {
                ScrollView {
                    VStack(spacing: 0) {
                        heading
                        if showsDetails { detailContent }
                        actionArea
                    }
                }
                .frame(maxHeight: maxPanelHeight)
                .scrollBounceBehavior(.basedOnSize)
                .contentMargins(.bottom, AppSpacing.sm, for: .scrollContent)
            } else {
                VStack(spacing: 0) {
                    heading
                    if showsDetails {
                        ScrollView { detailContent }
                            .frame(maxHeight: maxContentHeight)
                            .scrollBounceBehavior(.basedOnSize)
                            .contentMargins(.bottom, AppSpacing.sm, for: .scrollContent)
                            .clipped()
                    }
                    actionArea
                }
                .frame(maxHeight: maxPanelHeight)
            }
        }
        .foregroundStyle(AppColors.primaryText)
        .background(AppColors.surface)
        .clipped()
        .overlay(alignment: .top) {
            Rectangle().fill(AppColors.border).frame(height: 1).allowsHitTesting(false)
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: AppSpacing.xs) {
                Rectangle().fill(AppColors.accent).frame(width: 3, height: 16)
                    .accessibilityHidden(true)
                AppSectionHeader(title: title, subtitle: subtitle)
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(AppTypography.supporting)
                            .frame(minWidth: AppSize.touchTarget, minHeight: AppSize.touchTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColors.secondaryText)
                    .accessibilityLabel(String(localized: "关闭详情"))
                }
            }
            .padding(.leading, AppSpacing.md)
            .padding(.trailing, AppSpacing.xxs)
            .padding(.vertical, AppSpacing.xs)

            if let summaryText {
                Text(summaryText)
                    .font(AppTypography.supporting.monospacedDigit())
                    .foregroundStyle(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.bottom, AppSpacing.xs)
            }

            if placement == .bottom {
                Button {
                    withAnimation(AppMotion.panel(reduceMotion: reduceMotion)) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: AppSpacing.xs) {
                        Text(disclosureTitle).font(AppTypography.supporting)
                        Spacer(minLength: AppSpacing.xs)
                        Text(isExpanded ? String(localized: "收起") : String(localized: "展开")).font(AppTypography.caption)
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                            .font(AppTypography.caption)
                    }
                    .foregroundStyle(AppColors.secondaryText)
                    .padding(.horizontal, AppSpacing.md)
                    .frame(minHeight: AppSize.touchTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(disclosureTitle)
                .accessibilityValue(isExpanded ? String(localized: "已展开") : String(localized: "已折叠"))
                .overlay(alignment: .top) { Divider().overlay(AppColors.border) }
            }
        }
    }

    private var detailContent: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.md)
    }

    private var actionArea: some View {
        actions()
            .padding(.horizontal, AppSpacing.xs)
            .padding(.vertical, AppSpacing.xxs)
            .overlay(alignment: .top) { Divider().overlay(AppColors.border) }
    }
}
