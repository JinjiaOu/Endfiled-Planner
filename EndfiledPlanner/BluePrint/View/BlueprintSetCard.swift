// Created by Jinjia Ou on 2/21/26.

import SwiftUI

struct BlueprintSetCard: View {
    let blueprintSet: BlueprintSet

    var body: some View {
        AppSurface {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                BlueprintLocation(region: blueprintSet.region, location: blueprintSet.location)
                Text(blueprintSet.name).font(AppTypography.sectionTitle)
                    .foregroundStyle(AppColors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Label(blueprintSet.author, systemImage: "person")
                    .font(AppTypography.supporting).foregroundStyle(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if !blueprintSet.description.isEmpty {
                    Text(blueprintSet.description).font(AppTypography.supporting)
                        .foregroundStyle(AppColors.secondaryText).lineLimit(3)
                }
                Divider().overlay(AppColors.border)
                HStack(spacing: AppSpacing.xs) {
                    Label(String(localized: "\(blueprintSet.blueprints.count) 个蓝图"), systemImage: "square.stack")
                        .font(AppTypography.caption.monospacedDigit())
                    Spacer(minLength: AppSpacing.xs)
                    Image(systemName: "chevron.right").font(AppTypography.caption)
                }
                .foregroundStyle(AppColors.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

struct BlueprintLocation: View {
    let region: String
    let location: String

    var body: some View {
        Label(location.isEmpty ? DisplayName.region(region) : "\(DisplayName.region(region)) · \(location)", systemImage: "map")
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}
