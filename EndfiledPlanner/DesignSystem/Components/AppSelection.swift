// Created by Jinjia Ou on 10/19/26.

import SwiftUI

struct AppSearchField: View {
    @Binding var text: String
    var prompt = "搜索"
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppColors.secondaryText)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.primaryText)
                .focused($isFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .accessibilityLabel(prompt)
            if !text.isEmpty {
                AppIconButton(title: "清除搜索", systemImage: "xmark.circle.fill") { text = "" }
            }
        }
        .padding(.leading, AppSpacing.sm)
        .padding(.trailing, text.isEmpty ? AppSpacing.sm : AppSpacing.xxs)
        .frame(minHeight: AppSize.rowMinimum)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: AppRadius.control))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.control)
                .strokeBorder(isFocused ? AppColors.accent : AppColors.controlBorder,
                              lineWidth: isFocused ? 2 : 1)
                .allowsHitTesting(false)
        }
    }
}

struct AppFilterChip<Icon: View>: View {
    let title: String
    var isSelected = false
    var action: () -> Void
    @ViewBuilder var icon: () -> Icon

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.xs) {
                icon().accessibilityHidden(true)
                Text(title).font(AppTypography.rowTitle)
                if isSelected {
                    Image(systemName: "checkmark").font(AppTypography.caption.weight(.bold))
                }
            }
            .foregroundStyle(isSelected ? AppColors.onAccent : AppColors.primaryText)
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.xs)
            .frame(minHeight: AppSize.touchTarget)
            .background(isSelected ? AppColors.accentFill : AppColors.elevatedSurface, in: Capsule())
            .overlay { Capsule().strokeBorder(AppColors.controlBorder, lineWidth: 1).allowsHitTesting(false) }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension AppFilterChip where Icon == EmptyView {
    init(title: String, isSelected: Bool = false, action: @escaping () -> Void) {
        self.init(title: title, isSelected: isSelected, action: action, icon: { EmptyView() })
    }
}

struct AppSelectionRow<Icon: View>: View {
    let title: String
    var subtitle: String? = nil
    var isSelected = false
    var multiSelect = false
    var restriction: String? = nil
    var isSelectable = true
    var hint = ""
    var action: () -> Void
    @ViewBuilder var icon: () -> Icon

    private var spokenLabel: String {
        [title, subtitle, restriction].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "，")
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: AppSpacing.sm) {
                icon().accessibilityHidden(true)
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text(title).font(AppTypography.rowTitle)
                        .foregroundStyle(isSelectable ? AppColors.primaryText : AppColors.disabledText)
                    if let subtitle {
                        Text(subtitle).font(AppTypography.supporting).foregroundStyle(AppColors.secondaryText)
                    }
                    if let restriction {
                        Label(restriction, systemImage: "info.circle")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.secondaryText)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                if multiSelect || isSelected {
                    Image(systemName: multiSelect
                          ? (isSelected ? "checkmark.square.fill" : "square")
                          : "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(isSelected ? AppColors.accent : AppColors.controlBorder)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, AppSpacing.sm)
            .frame(minHeight: AppSize.rowMinimum)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isSelectable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityValue(isSelected ? "已选择" : "未选择")
        .accessibilityHint(hint)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
