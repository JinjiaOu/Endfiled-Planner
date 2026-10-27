// Created by Jinjia Ou on 10/19/26.

import SwiftUI

/// value 已由调用方按原口径计算、格式化；本组件不做单位换算。
struct AppMetricCell: View {
    let title: String
    let value: String
    var unit: String? = nil
    var detail: String? = nil
    var tone: AppStatusTone = .neutral

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(verbatim: title).font(AppTypography.supporting).foregroundStyle(AppColors.secondaryText)
            Text(verbatim: value).font(AppTypography.metric)
                .foregroundStyle(tone == .neutral ? AppColors.primaryText : tone.color)
            if let unit {
                Text(verbatim: unit).font(AppTypography.caption).foregroundStyle(AppColors.secondaryText)
            }
            if let detail {
                Text(detail).font(AppTypography.supporting).foregroundStyle(AppColors.secondaryText)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([title, value, unit, detail].compactMap { $0 }.joined(separator: "，"))
    }
}

struct AppMetricGrid<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ViewBuilder var content: () -> Content

    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible(), alignment: .topLeading)]
            : [GridItem(.adaptive(minimum: AppSize.metricColumnMinimum),
                        spacing: AppSpacing.md, alignment: .topLeading)]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: AppSpacing.md, content: content)
    }
}

struct AppKeyValueRow: View {
    let title: String
    let value: String
    var detail: String? = nil
    var valueColor: Color = AppColors.primaryText
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            if dynamicTypeSize.isAccessibilitySize {
                verticalContent
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: AppSpacing.md) {
                        Text(verbatim: title).font(AppTypography.rowTitle).foregroundStyle(AppColors.secondaryText)
                            .fixedSize()
                        Spacer(minLength: AppSpacing.md)
                        valueText.fixedSize()
                    }
                    verticalContent
                }
            }
            if let detail {
                Text(detail).font(AppTypography.supporting).foregroundStyle(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var valueText: some View {
        Text(verbatim: value).font(AppTypography.numeric).foregroundStyle(valueColor)
    }

    private var verticalContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text(verbatim: title).font(AppTypography.rowTitle).foregroundStyle(AppColors.secondaryText)
            valueText
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
