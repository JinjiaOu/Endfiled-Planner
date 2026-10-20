// Created by Jinjia Ou on 10/20/26.

import SwiftUI

/// 文档型提示：低高度及大字号下标题、条款与操作均可滚动访问。
struct AppNoticeDialog<Content: View, Actions: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.55).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.lg) {
                        Label(title, systemImage: "exclamationmark.triangle")
                            .font(AppTypography.sectionTitle).foregroundStyle(AppColors.primaryText)
                            .accessibilityAddTraits(.isHeader)
                        Divider().overlay(AppColors.border)
                        content()
                        Divider().overlay(AppColors.border)
                        actions()
                    }
                    .padding(AppSpacing.lg)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxWidth: 560)
                .frame(maxHeight: max(100, min(640, geometry.size.height - AppSpacing.xl)))
                .background(AppColors.surface, in: RoundedRectangle(cornerRadius: AppRadius.surface))
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.surface))
                .overlay {
                    RoundedRectangle(cornerRadius: AppRadius.surface).strokeBorder(AppColors.border, lineWidth: 1)
                }
                .padding(.horizontal, AppSpacing.md)
            }
        }
        .tint(AppColors.accent)
    }
}
