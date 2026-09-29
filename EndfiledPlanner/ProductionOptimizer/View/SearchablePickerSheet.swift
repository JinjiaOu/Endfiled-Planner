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
    var chipsLabel: String = "按原料筛选"

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var activeChip: String? = nil

    private let accent = Color(red: 0.9, green: 0.5, blue: 0.2)
    private let background = Color(red: 0.08, green: 0.09, blue: 0.12)

    private var filteredItems: [SearchablePickerItem] {
        var result = items
        if let activeChip {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(activeChip) ||
                ($0.subtitle?.localizedCaseInsensitiveContains(activeChip) ?? false)
            }
        }
        let keyword = searchText.trimmingCharacters(in: .whitespaces)
        guard !keyword.isEmpty else { return result }
        return result.filter {
            $0.title.localizedCaseInsensitiveContains(keyword) ||
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
                    row(title: item.title, subtitle: item.subtitle, isSelected: isSelected) {
                        if multiSelect {
                            onToggle?(item.id)
                        } else {
                            onSelect?(item.id)
                            dismiss()
                        }
                    }
                }
                if filteredItems.isEmpty {
                    Text("没有匹配的结果")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(background)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(background, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                if multiSelect {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { dismiss() }
                            .foregroundColor(accent)
                    }
                } else {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") { dismiss() }
                            .foregroundColor(accent)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var chipRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(chipsLabel)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(filterChips, id: \.self) { chip in
                        let isOn = activeChip == chip
                        Button {
                            activeChip = isOn ? nil : chip
                        } label: {
                            Text(chip)
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(isOn ? accent : Color.white.opacity(0.1))
                                .foregroundColor(isOn ? .black : .white.opacity(0.8))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
        .padding(.horizontal, 4).padding(.vertical, 6)
    }

    private func row(title: String, subtitle: String?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if multiSelect {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .foregroundColor(isSelected ? accent : .white.opacity(0.3))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                Spacer()
                if !multiSelect && isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(accent)
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(isSelected ? accent.opacity(0.12) : Color.clear)
    }
}
