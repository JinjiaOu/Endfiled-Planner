//
//  SearchView.swift
//  EndfiledPlanner
//
//  Created by Jinjia Ou on 2/14/26.
//

import SwiftUI
import Combine

// MARK: - 搜索历史管理

class SearchHistoryManager: ObservableObject {
    private let key = "recipeSearchHistory"
    private let maxCount = 8
    
    @Published var history: [String] = []
    
    init() {
        history = UserDefaults.standard.stringArray(forKey: key) ?? []
    }
    
    func add(_ item: String) {
        var updated = history.filter { $0 != item }
        updated.insert(item, at: 0)
        if updated.count > maxCount { updated = Array(updated.prefix(maxCount)) }
        history = updated
        UserDefaults.standard.set(updated, forKey: key)
    }
    
    func remove(_ item: String) {
        history.removeAll { $0 == item }
        UserDefaults.standard.set(history, forKey: key)
    }
    
    func clear() {
        history = []
        UserDefaults.standard.removeObject(forKey: key)
    }
}

// MARK: - 联想结果模型

struct SuggestionItem: Identifiable {
    let id = UUID()
    let name: String
    let matchType: MatchType
    
    enum MatchType {
        case history
        case prefixMatch
        case containsMatch
    }
}

// MARK: - SearchView

struct SearchView: View {
    
    @StateObject var vm = RecipeViewModel()
    @StateObject private var historyMgr = SearchHistoryManager()
    
    @State private var selectedItem: String?
    @State private var amount: Int = 1
    @State private var showTree = false
    @State private var showDetailView = false
    
    @State private var searchText: String = ""
    @State private var showDropdown: Bool = false
    @FocusState private var searchFocused: Bool
    
    // 免责声明：@AppStorage 保证只弹一次
    @AppStorage("recipeDisclaimerSeen") private var disclaimerSeen = false
    @State private var showDisclaimer = false
    @State private var showEmptyHint = false
    @State private var pageWidth: CGFloat = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var suggestions: [SuggestionItem] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if query.isEmpty {
            return historyMgr.history.map { SuggestionItem(name: $0, matchType: .history) }
        }
        let all = vm.recipes.keys.sorted()
        let prefix   = all.filter { DisplayName.hasPrefix($0, query: query) }
        let contains = all.filter {
            !DisplayName.hasPrefix($0, query: query) &&
            DisplayName.matches($0, query: query)
        }
        return prefix.map  { SuggestionItem(name: $0, matchType: .prefixMatch)   }
             + contains.map { SuggestionItem(name: $0, matchType: .containsMatch) }
    }
    
    var body: some View {
        ZStack {
            AppTopographicBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    AppPageHeader(title: String(localized: "分析生产依赖"), subtitle: String(localized: "选择目标物品与数量，查看生产步骤和串行耗时。"))
                    if pageWidth >= 820 && !dynamicTypeSize.isAccessibilitySize {
                        HStack(alignment: .top, spacing: AppSpacing.lg) {
                            configuration.frame(width: 320)
                            results.frame(maxWidth: .infinity)
                        }
                    } else {
                        configuration
                        results
                    }
                }
                .padding(AppSpacing.md)
                .frame(maxWidth: 1120, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)

            if showDisclaimer {
                RecipeDisclaimerOverlay {
                    withAnimation(AppMotion.feedback(reduceMotion: reduceMotion)) {
                        showDisclaimer = false
                        disclaimerSeen = true
                    }
                }
                .zIndex(10)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { pageWidth = $0 }
        .navigationTitle(String(localized: "配方分析"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(AppColors.background, for: .navigationBar)
        .tint(AppColors.accent)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(String(localized: "完成")) { dismissDropdown() }
            }
        }
        .sheet(isPresented: $showDetailView) {
            if let root = vm.rootNode { RecipeDetailView(root: root) }
        }
        .onAppear {
            if !disclaimerSeen {
                withAnimation(AppMotion.feedback(reduceMotion: reduceMotion)) { showDisclaimer = true }
            }
        }
    }

    private var configuration: some View {
        AppSurface {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                AppSectionHeader(title: String(localized: "目标与数量"))
                searchInput
                if showDropdown {
                    SuggestionDropdown(suggestions: suggestions, searchText: searchText,
                                       selectedItem: selectedItem, historyMgr: historyMgr,
                                       onSelect: selectItem,
                                       onDeleteHistory: { historyMgr.remove($0) },
                                       onClearHistory: { historyMgr.clear() })
                }
                if let selectedItem {
                    Label { Text(verbatim: DisplayName.item(selectedItem)) } icon: { Image(systemName: "checkmark.circle.fill") }
                        .font(AppTypography.supporting).foregroundStyle(AppColors.success)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider().overlay(AppColors.border)
                Stepper(value: $amount, in: 1...100) {
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text(String(localized: "目标数量")).font(AppTypography.supporting).foregroundStyle(AppColors.secondaryText)
                        Text("\(amount)").font(AppTypography.metric).foregroundStyle(AppColors.primaryText)
                    }
                }
                .accessibilityLabel(String(localized: "目标数量"))
                .accessibilityValue("\(amount)")
                Button(action: buildRecipe) {
                    Label(String(localized: "查看配方"), systemImage: "arrow.triangle.branch")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(AppActionStyle())
                if showEmptyHint {
                    AppInlineNotice(title: String(localized: "请先搜索或选择一个配方"), tone: .warning)
                }
            }
        }
    }

    private var searchInput: some View {
        HStack(alignment: .top, spacing: AppSpacing.xs) {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "magnifyingglass").foregroundStyle(AppColors.secondaryText)
                ZStack(alignment: .leading) {
                    if showDropdown, !searchText.isEmpty, let first = suggestions.first,
                       first.matchType == .prefixMatch, first.name.count > searchText.count {
                        Text(verbatim: DisplayName.item(first.name)).foregroundStyle(AppColors.tertiaryText.opacity(0.45))
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                    TextField(String(localized: "搜索物品"), text: $searchText)
                        .focused($searchFocused)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.search)
                        .onChange(of: searchFocused) { _, focused in
                            withAnimation(AppMotion.feedback(reduceMotion: reduceMotion)) { showDropdown = focused }
                        }
                        .onChange(of: searchText) { _, _ in
                            if !showDropdown { showDropdown = true }
                        }
                        .onSubmit { if let first = suggestions.first { selectItem(first.name) } }
                        .accessibilityLabel(String(localized: "搜索目标物品"))
                }
                .font(AppTypography.body).foregroundStyle(AppColors.primaryText)
                if !searchText.isEmpty {
                    AppIconButton(title: String(localized: "清除物品搜索"), systemImage: "xmark.circle.fill") {
                        searchText = ""
                        selectedItem = nil
                    }
                }
            }
            .padding(.leading, AppSpacing.sm)
            .padding(.trailing, searchText.isEmpty ? AppSpacing.sm : 0)
            .frame(minHeight: AppSize.rowMinimum)
            .background(AppColors.background, in: RoundedRectangle(cornerRadius: AppRadius.control))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.control)
                    .strokeBorder(searchFocused ? AppColors.accent : AppColors.controlBorder, lineWidth: 1)
                    .allowsHitTesting(false)
            }
            Menu {
                ForEach(vm.recipes.keys.sorted(), id: \.self) { item in
                    Button { selectItem(item) } label: { Text(verbatim: DisplayName.item(item)) }
                }
            } label: {
                Image(systemName: "list.bullet")
                    .frame(minWidth: AppSize.touchTarget, minHeight: AppSize.rowMinimum)
                    .background(AppColors.background, in: RoundedRectangle(cornerRadius: AppRadius.control))
            }
            .accessibilityLabel(String(localized: "浏览全部物品"))
        }
    }

    @ViewBuilder
    private var results: some View {
        if showTree, let root = vm.rootNode {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                AppSurface {
                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        AppSectionHeader(title: DisplayName.item(root.name), subtitle: String(localized: "分析结果 · 目标数量 \(root.amount)"))
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading),
                                                 count: dynamicTypeSize.isAccessibilitySize ? 1 : 3),
                                  alignment: .leading, spacing: AppSpacing.md) {
                            EndFieldStatCard(icon: "clock", title: String(localized: "串行耗时"), value: "\(root.totalTime)", unit: String(localized: "秒"), color: AppColors.primaryText)
                            EndFieldStatCard(icon: "gearshape.2", title: String(localized: "生产批次"), value: "\(root.batches)", unit: String(localized: "批"), color: AppColors.primaryText)
                            EndFieldStatCard(icon: "arrow.triangle.branch", title: String(localized: "依赖节点"), value: "\(countNodes(root))", unit: String(localized: "个"), color: AppColors.primaryText)
                        }
                        Text(String(localized: "耗时为最长串行路径，不含采集、运输和实际产线调度。"))
                            .font(AppTypography.caption).foregroundStyle(AppColors.secondaryText)
                    }
                }
                AppSurface(padding: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        AppSectionHeader(title: String(localized: "配方树"), subtitle: String(localized: "展开查看完整依赖，支持缩放、保存与分享。"))
                            .padding(AppSpacing.md)
                        Divider().overlay(AppColors.border)
                        Button { dismissDropdown(); showDetailView = true } label: {
                            ThumbnailPreview(root: root).frame(height: 260)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "查看完整配方树"))
                        Button { dismissDropdown(); showDetailView = true } label: {
                            Label(String(localized: "展开完整配方树"), systemImage: "arrow.up.left.and.arrow.down.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(AppActionStyle(emphasis: .secondary))
                        .padding(AppSpacing.sm)
                    }
                }
            }
        } else if showTree {
            AppSurface {
                AppContentState(title: String(localized: "未找到配方数据"), message: String(localized: "请重新选择目标物品后分析。"),
                                systemImage: "exclamationmark.triangle", tone: .error)
            }
        } else {
            AppSurface {
                AppContentState(title: String(localized: "从目标物品开始"), message: String(localized: "输入名称、选择搜索历史，或浏览全部物品；选择数量后查看生产依赖。"),
                                systemImage: "arrow.triangle.branch")
            }
        }
    }

    private func buildRecipe() {
        if let item = selectedItem {
            showEmptyHint = false
            dismissDropdown()
            withAnimation(AppMotion.feedback(reduceMotion: reduceMotion)) {
                vm.buildTree(target: item, amount: amount)
                showTree = true
            }
        } else {
            withAnimation(AppMotion.feedback(reduceMotion: reduceMotion)) { showEmptyHint = true }
        }
    }

    // MARK: - 辅助方法
    
    private func selectItem(_ item: String) {
        withAnimation(AppMotion.feedback(reduceMotion: reduceMotion)) {
            selectedItem = item
            searchText = DisplayName.item(item)
            showDropdown = false
            searchFocused = false
            showEmptyHint = false
        }
        historyMgr.add(item)
    }
    
    private func dismissDropdown() {
        withAnimation(AppMotion.feedback(reduceMotion: reduceMotion)) {
            showDropdown = false
            searchFocused = false
        }
    }
    
    private func countNodes(_ node: RecipeNode) -> Int {
        1 + node.children.reduce(0) { $0 + countNodes($1) }
    }
}

// MARK: - 免责声明弹窗

struct RecipeDisclaimerOverlay: View {
    let onConfirm: () -> Void

    var body: some View {
        AppNoticeDialog(title: String(localized: "时间数据说明")) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                DisclaimerRow(icon: "arrow.triangle.branch",
                              text: String(localized: "本功能展示的生产时间基于单条串行链路计算，即从原材料到成品的最长路径耗时。"))
                DisclaimerRow(icon: "minus.circle",
                              text: "计算结果不包含采矿、种植等原材料采集环节的时间，亦未考虑传送带运输延迟、建筑数量限制、产线调度等实际因素。")
                DisclaimerRow(icon: "info.circle",
                              text: String(localized: "展示数据仅供规划参考，实际生产效率以游戏内表现为准。"))
            }
        } actions: {
            Button(action: onConfirm) {
                Label(String(localized: "我已了解"), systemImage: "checkmark").frame(maxWidth: .infinity)
            }
            .buttonStyle(AppActionStyle())
        }
    }
}

struct DisclaimerRow: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            Image(systemName: icon).foregroundStyle(AppColors.accent)
                .frame(width: AppSize.icon)
            Text(text).font(AppTypography.body).foregroundStyle(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - 联想下拉列表

struct SuggestionDropdown: View {
    let suggestions: [SuggestionItem]
    let searchText: String
    let selectedItem: String?
    let historyMgr: SearchHistoryManager
    let onSelect: (String) -> Void
    let onDeleteHistory: (String) -> Void
    let onClearHistory: () -> Void
    
    
    private var groups: [(label: String, icon: String, items: [SuggestionItem])] {
        let history  = suggestions.filter { $0.matchType == .history }
        let prefix   = suggestions.filter { $0.matchType == .prefixMatch }
        let contains = suggestions.filter { $0.matchType == .containsMatch }
        var g: [(String, String, [SuggestionItem])] = []
        if !history.isEmpty  { g.append((String(localized: "最近搜索"),    "clock.arrow.circlepath", history))  }
        if !prefix.isEmpty   { g.append((String(localized: "前缀匹配"), "target",                 prefix))   }
        if !contains.isEmpty { g.append((String(localized: "包含匹配"),   "text.magnifyingglass",   contains)) }
        return g
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if suggestions.isEmpty {
                Text(searchText.isEmpty ? String(localized: "暂无搜索历史") : String(localized: "未找到匹配物品"))
                    .font(AppTypography.supporting).foregroundStyle(AppColors.secondaryText)
                    .padding(AppSpacing.sm)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                            HStack {
                                Label(group.label, systemImage: group.icon)
                                    .font(AppTypography.caption).foregroundStyle(AppColors.secondaryText)
                                Spacer()
                                if group.items.first?.matchType == .history {
                                    Button(String(localized: "清除")) { onClearHistory() }
                                        .font(AppTypography.caption)
                                        .frame(minWidth: AppSize.touchTarget, minHeight: AppSize.touchTarget)
                                        .accessibilityLabel(String(localized: "清除全部搜索历史"))
                                }
                            }
                            ForEach(group.items) { item in
                                HStack(spacing: AppSpacing.xs) {
                                    Button { onSelect(item.name) } label: {
                                        HStack(spacing: AppSpacing.xs) {
                                            ItemIcon(name: item.name, size: AppSize.itemIcon)
                                            HighlightedText(text: DisplayName.item(item.name), highlight: searchText,
                                                            baseColor: AppColors.primaryText, highlightColor: AppColors.accent)
                                                .font(AppTypography.rowTitle)
                                                .fixedSize(horizontal: false, vertical: true)
                                            Spacer(minLength: 0)
                                            if item.name == selectedItem {
                                                Image(systemName: "checkmark").foregroundStyle(AppColors.accent)
                                            }
                                        }
                                        .frame(minHeight: AppSize.touchTarget)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityAddTraits(item.name == selectedItem ? .isSelected : [])
                                    if item.matchType == .history {
                                        AppIconButton(title: String(localized: "删除历史：\(DisplayName.item(item.name))"), systemImage: "xmark") {
                                            onDeleteHistory(item.name)
                                        }
                                    }
                                }
                                Divider().overlay(AppColors.border)
                            }
                        }
                    }
                    .padding(.horizontal, AppSpacing.sm)
                }
                .frame(maxHeight: 280)
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .background(AppColors.background, in: RoundedRectangle(cornerRadius: AppRadius.control))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.control).strokeBorder(AppColors.border, lineWidth: 1)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - 高亮文字

struct HighlightedText: View {
    let text: String
    let highlight: String
    let baseColor: Color
    let highlightColor: Color
    
    var body: some View {
        highlight.isEmpty ? Text(text).foregroundColor(baseColor) : build()
    }
    
    private func build() -> Text {
        let lower = text.lowercased(), lowHL = highlight.lowercased()
        var result = Text(""), idx = lower.startIndex
        while idx < lower.endIndex {
            if let r = lower.range(of: lowHL, range: idx..<lower.endIndex) {
                if idx < r.lowerBound {
                    result = result + Text(String(text[idx..<r.lowerBound])).foregroundColor(baseColor)
                }
                result = result + Text(String(text[r])).foregroundColor(highlightColor).fontWeight(.bold)
                idx = r.upperBound
            } else {
                result = result + Text(String(text[idx...])).foregroundColor(baseColor)
                break
            }
        }
        return result
    }
}

// MARK: - 统计卡片

struct EndFieldStatCard: View {
    let icon: String; let title: String; let value: String; let unit: String; let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Label(title, systemImage: icon).font(AppTypography.caption).foregroundStyle(AppColors.secondaryText)
            Text(value).font(AppTypography.metric).foregroundStyle(color)
            Text(unit).font(AppTypography.caption).foregroundStyle(AppColors.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 缩略图预览

struct ThumbnailPreview: View {
    let root: RecipeNode
    private let nW: CGFloat = 80, nH: CGFloat = 50, xS: CGFloat = 90, yS: CGFloat = 70
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Canvas { ctx, _ in drawLines(node: root, ctx: &ctx) }
                ThumbnailNodeView(node: root, nodeWidth: nW, nodeHeight: nH, xSpacing: xS, ySpacing: yS)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .scaleEffect(calcScale(in: geo.size))
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .clipped()
    }
    
    private func calcScale(in size: CGSize) -> CGFloat {
        let w = (maxX(root) + 1) * xS, h = CGFloat(maxLv(root) + 1) * yS
        return min((size.width - 40) / w, (size.height - 40) / h, 1.0)
    }
    private func maxX(_ n: RecipeNode) -> CGFloat { n.children.reduce(n.positionX) { max($0, maxX($1)) } }
    private func maxLv(_ n: RecipeNode) -> Int     { n.children.reduce(n.level)     { max($0, maxLv($1)) } }
    
    private func drawLines(node: RecipeNode, ctx: inout GraphicsContext) {
        for child in node.children {
            let s = CGPoint(x: child.positionX * xS + nW/2, y: CGFloat(child.level) * yS - nH/2)
            let e = CGPoint(x: node.positionX  * xS + nW/2, y: CGFloat(node.level)  * yS + nH/2)
            var p = Path(); p.move(to: s)
            p.addCurve(to: e, control1: CGPoint(x: s.x, y: s.y+(e.y-s.y)*0.5), control2: CGPoint(x: e.x, y: s.y+(e.y-s.y)*0.5))
            ctx.stroke(p, with: .color(AppColors.accent.opacity(0.3)), lineWidth: 1.5)
            drawLines(node: child, ctx: &ctx)
        }
    }
}

struct ThumbnailNodeView: View {
    let node: RecipeNode
    let nodeWidth, nodeHeight, xSpacing, ySpacing: CGFloat
    
    var body: some View {
        ZStack {
            thumb(node).position(x: node.positionX * xSpacing + nodeWidth/2, y: CGFloat(node.level) * ySpacing)
            ForEach(node.children) { child in
                ThumbnailNodeView(node: child, nodeWidth: nodeWidth, nodeHeight: nodeHeight, xSpacing: xSpacing, ySpacing: ySpacing)
            }
        }
    }
    
    private func thumb(_ node: RecipeNode) -> some View {
        RecipeDiagramCard(node: node, compact: true)
            .frame(width: nodeWidth, height: nodeHeight)
    }
}
