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

/// 全屏搜索选择弹窗：长列表（取货材料 170+ 个、多配方）用原生 Menu 很难点选，换成大行高 + 搜索框
struct SearchablePickerSheet: View {
    let title: String
    let items: [SearchablePickerItem]
    let selectedID: String?
    /// 非 nil 时在列表顶部多一行"清空选择"，选中后回调 nil
    var clearTitle: String? = nil
    let onSelect: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private let accent = Color(red: 0.9, green: 0.5, blue: 0.2)
    private let background = Color(red: 0.08, green: 0.09, blue: 0.12)

    private var filteredItems: [SearchablePickerItem] {
        let keyword = searchText.trimmingCharacters(in: .whitespaces)
        guard !keyword.isEmpty else { return items }
        return items.filter {
            $0.title.localizedCaseInsensitiveContains(keyword) ||
            ($0.subtitle?.localizedCaseInsensitiveContains(keyword) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if let clearTitle, searchText.isEmpty {
                    row(title: clearTitle, subtitle: nil, isSelected: selectedID == nil) {
                        onSelect(nil)
                        dismiss()
                    }
                }
                ForEach(filteredItems) { item in
                    row(title: item.title, subtitle: item.subtitle, isSelected: item.id == selectedID) {
                        onSelect(item.id)
                        dismiss()
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                        .foregroundColor(accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func row(title: String, subtitle: String?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
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
                if isSelected {
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
