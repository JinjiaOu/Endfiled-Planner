//
//  SearchablePickerSheet.swift
//  EndfiledPlanner
//
//  Created by Jinjia Ou on 9/20/26.
//

import SwiftUI

struct SearchablePickerItem: Identifiable {
    let id: String
    let title: String
    var subtitle: String? = nil
    var iconName: String? = nil
    /// 非 nil 时这一行标灰、点不了，右边显示这段标签（比如四号谷地里液体模式配方标"仅武陵"）；
    /// 多选模式下已经勾上的还能取消勾选
    var disabledTag: String? = nil
    var searchTerms: String = ""
}

/// 全屏搜索选择弹窗：长列表（取货材料 170+ 个、多配方）用原生 Menu 很难点选，换成大行高 + 搜索框。
/// 单选模式：点一下就选中并关闭。多选模式（`multiSelect: true`）：点击只切换勾选，不关闭，用右上角"完成"关闭。
struct SearchablePickerSheet: View {
    let title: String
    let items: [SearchablePickerItem]
    var multiSelect: Bool = false
    /// 单选模式用
    var selectedID: String? = nil
    /// 非 nil 时在列表顶部多一行"清空选择"，选中后回调 nil（仅单选模式）
    var clearTitle: String? = nil
    var onSelect: ((String?) -> Void)? = nil
    /// 多选模式用
    var selectedIDs: Set<String> = []
    var onToggle: ((String) -> Void)? = nil
    /// 顶部的筛选标签（比如"这台机器能吃的所有原料名"），点一下按标签筛列表，跟游戏里"先选原料再看配方"一个思路；
    /// 不传就不显示这一排
    var filterChips: [String] = []
    var chipsLabel: String = String(localized: "按原料筛选")

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var activeChip: String? = nil

    private var filteredItems: [SearchablePickerItem] {
        var result = items
        if let activeChip {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(DisplayName.item(activeChip)) ||
                ($0.subtitle?.localizedCaseInsensitiveContains(DisplayName.item(activeChip)) ?? false)
            }
        }
        let keyword = searchText.trimmingCharacters(in: .whitespaces)
        guard !keyword.isEmpty else { return result }
        return result.filter {
            $0.title.localizedCaseInsensitiveContains(keyword) ||
            DisplayName.matches($0.iconName ?? "", query: keyword) ||
            $0.searchTerms.localizedCaseInsensitiveContains(keyword) ||
            ($0.subtitle?.localizedCaseInsensitiveContains(keyword) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if !filterChips.isEmpty {
                    chipRow
                }
                if !multiSelect, let clearTitle, searchText.isEmpty {
                    row(title: clearTitle, subtitle: nil, isSelected: selectedID == nil) {
                        onSelect?(nil)
                        dismiss()
                    }
                }
                ForEach(filteredItems) { item in
                    let isSelected = multiSelect ? selectedIDs.contains(item.id) : item.id == selectedID
                    row(title: item.title, subtitle: item.subtitle, iconName: item.iconName, isSelected: isSelected,
                        disabledTag: item.disabledTag) {
                        if item.disabledTag != nil && !(multiSelect && isSelected) { return }
                        if multiSelect {
                            onToggle?(item.id)
                        } else {
                            onSelect?(item.id)
                            dismiss()
                        }
                    }
                }
                if filteredItems.isEmpty {
                    AppContentState(title: String(localized: "没有匹配的结果"),
                                    message: filterChips.isEmpty ? String(localized: "请尝试其他关键词。") : String(localized: "请尝试其他关键词，或取消原料筛选。"),
                                    systemImage: "magnifyingglass")
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(AppColors.background)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: String(localized: "搜索"))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(AppColors.background, for: .navigationBar)
            .toolbar {
                if multiSelect {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "完成")) { dismiss() }
                            .tint(AppColors.accent)
                    }
                } else {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "关闭")) { dismiss() }
                            .tint(AppColors.accent)
                    }
                }
            }
        }
        .appPageStyle()
    }

    private var chipRow: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(chipsLabel)
                .font(AppTypography.supporting)
                .foregroundStyle(AppColors.secondaryText)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.xs) {
                    ForEach(filterChips, id: \.self) { chip in
                        let isOn = activeChip == chip
                        AppFilterChip(title: DisplayName.item(chip), isSelected: isOn, action: {
                            activeChip = isOn ? nil : chip
                        }) {
                            ItemIcon(name: chip, size: AppSize.icon)
                        }
                    }
                }
            }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets())
        .padding(.horizontal, AppSpacing.md).padding(.vertical, AppSpacing.sm)
    }

    private func row(title: String, subtitle: String?, iconName: String? = nil, isSelected: Bool,
                     disabledTag: String? = nil, action: @escaping () -> Void) -> some View {
        AppSelectionRow(title: title, subtitle: subtitle, isSelected: isSelected,
                        multiSelect: multiSelect, restriction: disabledTag,
                        isSelectable: disabledTag == nil || (multiSelect && isSelected),
                        hint: disabledTag != nil && multiSelect && isSelected ? String(localized: "可取消选择") : "",
                        action: action) {
            if let iconName {
                ItemIcon(name: iconName, size: AppSize.itemIcon)
            }
        }
        .listRowBackground(isSelected ? AppColors.accent.opacity(0.12) : AppColors.surface)
        .listRowSeparatorTint(AppColors.border)
    }
}
