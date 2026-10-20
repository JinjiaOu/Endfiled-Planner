// Created by Jinjia Ou on 10/19/26.

import SwiftUI

struct AppActionStyle: ButtonStyle {
    enum Emphasis: Equatable { case primary, secondary, destructive }
    var emphasis: Emphasis = .primary
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var foreground: Color {
        guard isEnabled else { return AppColors.disabledText }
        switch emphasis {
        case .primary: return AppColors.onAccent
        case .secondary: return AppColors.primaryText
        case .destructive: return AppColors.error
        }
    }

    private var background: Color {
        guard isEnabled else { return AppColors.disabledSurface }
        switch emphasis {
        case .primary: return AppColors.accentFill
        case .secondary: return AppColors.elevatedSurface
        case .destructive: return AppColors.error.opacity(0.12)
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTypography.button)
            .foregroundStyle(foreground)
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .frame(minWidth: AppSize.touchTarget, minHeight: AppSize.touchTarget)
            .background(background, in: RoundedRectangle(cornerRadius: AppRadius.control))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.control)
                    .strokeBorder(emphasis == .primary ? Color.clear : AppColors.controlBorder, lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .opacity(configuration.isPressed && isEnabled ? 0.8 : 1)
            .animation(AppMotion.feedback(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

struct AppIconButton: View {
    let title: String
    let systemImage: String
    var action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(minWidth: AppSize.touchTarget, minHeight: AppSize.touchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? AppColors.accent : AppColors.disabledText)
        .accessibilityLabel(title)
        .help(title)
    }
}

/// 工具名称始终显示；外层决定换行或列数，不靠缩小文字容纳所有工具。
struct AppToolButton: View {
    let title: String
    let systemImage: String
    var isSelected = false
    var action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            VStack(spacing: AppSpacing.xxs) {
                Image(systemName: systemImage).font(.body.weight(.semibold))
                Text(title).font(AppTypography.caption).multilineTextAlignment(.center)
            }
            .foregroundStyle(isEnabled ? (isSelected ? AppColors.accent : AppColors.primaryText) : AppColors.disabledText)
            .padding(AppSpacing.xs)
            .frame(minWidth: AppSize.touchTarget, minHeight: AppSize.touchTarget)
            .background(isSelected ? AppColors.accent.opacity(0.12) : AppColors.surface,
                        in: RoundedRectangle(cornerRadius: AppRadius.control))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.control)
                    .strokeBorder(isSelected ? AppColors.accent : AppColors.border,
                                  lineWidth: isSelected ? 2 : 1)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
