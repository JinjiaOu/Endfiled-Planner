// Created by Jinjia Ou on 10/19/26.

import SwiftUI

/// 显示层语义。调用方提供业务状态的文字，不在组件中推断机器运行结果。
enum AppStatusTone: Equatable {
    case neutral, success, warning, error, info

    var color: Color {
        switch self {
        case .neutral: return AppColors.secondaryText
        case .success: return AppColors.success
        case .warning: return AppColors.warning
        case .error: return AppColors.error
        case .info: return AppColors.info
        }
    }

    var symbol: String {
        switch self {
        case .neutral: return "circle.dashed"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "exclamationmark.octagon.fill"
        case .info: return "info.circle.fill"
        }
    }
}

struct AppStatusBadge: View {
    let title: String
    var tone: AppStatusTone = .neutral

    var body: some View {
        Label(title, systemImage: tone.symbol)
            .font(AppTypography.caption.weight(.semibold))
            .foregroundStyle(tone.color)
            .padding(.horizontal, AppSpacing.xs)
            .padding(.vertical, AppSpacing.xxs)
            .background(tone.color.opacity(0.12), in: RoundedRectangle(cornerRadius: AppRadius.control))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
    }
}

struct AppInlineNotice: View {
    let title: String
    var message: String? = nil
    var tone: AppStatusTone = .info

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            Image(systemName: tone.symbol)
                .font(.body)
                .foregroundStyle(tone.color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(verbatim: title).font(AppTypography.rowTitle).foregroundStyle(AppColors.primaryText)
                if let message {
                    Text(verbatim: message).font(AppTypography.supporting).foregroundStyle(AppColors.secondaryText)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(AppSpacing.sm)
        .background(tone.color.opacity(0.08), in: RoundedRectangle(cornerRadius: AppRadius.control))
        .accessibilityElement(children: .combine)
    }
}

/// 空结果与错误共用排版，操作由调用方提供；不自动刷新或隐藏错误。
struct AppContentState<Actions: View>: View {
    let title: String
    let message: String
    var systemImage = "tray"
    var tone: AppStatusTone = .neutral
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Image(systemName: systemImage)
                .font(.title)
                .foregroundStyle(tone.color)
                .accessibilityHidden(true)
            AppSectionHeader(title: title, subtitle: message)
            actions()
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension AppContentState where Actions == EmptyView {
    init(title: String, message: String, systemImage: String = "tray", tone: AppStatusTone = .neutral) {
        self.init(title: title, message: message, systemImage: systemImage, tone: tone, actions: { EmptyView() })
    }
}

struct AppLoadingState: View {
    let title: String
    /// nil 表示无法量化的加载；有值时由调用方提供 0…1 的显示进度。
    var progress: Double? = nil
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            if let progress {
                ProgressView(value: progress) { Text(verbatim: title) }
            } else {
                HStack(spacing: AppSpacing.sm) {
                    ProgressView().accessibilityHidden(true)
                    Text(verbatim: title)
                }
            }
            if let detail {
                Text(detail).font(AppTypography.supporting).foregroundStyle(AppColors.secondaryText)
            }
        }
        .font(AppTypography.rowTitle)
        .foregroundStyle(AppColors.primaryText)
        .tint(AppColors.accent)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// 生命周期由业务页面持有，不在这里自动创建计时器或播报连续变化的数值。
struct AppFeedbackToast: View {
    let title: String
    var tone: AppStatusTone = .success

    var body: some View {
        Label(title, systemImage: tone.symbol)
            .font(AppTypography.rowTitle)
            .foregroundStyle(AppColors.primaryText)
            .padding(AppSpacing.md)
            .background(AppColors.elevatedSurface, in: RoundedRectangle(cornerRadius: AppRadius.surface))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.surface)
                    .strokeBorder(tone.color, lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
    }
}
