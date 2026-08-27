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
    
    var suggestions: [SuggestionItem] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if query.isEmpty {
            return historyMgr.history.map { SuggestionItem(name: $0, matchType: .history) }
        }
        let all = vm.recipes.keys.sorted()
        let prefix   = all.filter { $0.lowercased().hasPrefix(query.lowercased()) }
        let contains = all.filter {
            !$0.lowercased().hasPrefix(query.lowercased()) &&
            $0.localizedCaseInsensitiveContains(query)
        }
        return prefix.map  { SuggestionItem(name: $0, matchType: .prefixMatch)   }
             + contains.map { SuggestionItem(name: $0, matchType: .containsMatch) }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.08, green: 0.09, blue: 0.12).ignoresSafeArea()
                
                GeometryReader { _ in
                    Canvas { context, size in
                        let spacing: CGFloat = 30
                        var path = Path()
                        for x in stride(from: 0, through: size.width, by: spacing) {
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: size.height))
                        }
                        for y in stride(from: 0, through: size.height, by: spacing) {
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: size.width, y: y))
                        }
                        context.stroke(path,
                            with: .color(Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.1)),
                            lineWidth: 0.5)
                    }
                }
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 0) {
                        
                        // ── 控制面板 ─────────────────────────────────
                        VStack(spacing: 20) {
                            
                            // 标题
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 4) {
                                    Rectangle().fill(Color(red: 1.0, green: 0.8, blue: 0.0)).frame(width: 30, height: 2)
                                    Circle().fill(Color(red: 1.0, green: 0.8, blue: 0.0)).frame(width: 4, height: 4)
                                    Spacer()
                                }
                                Text("RECIPE ANALYSIS")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(Color(red: 1.0, green: 0.8, blue: 0.0))
                                Text("配方分析系统")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal)
                            .padding(.top, 20)
                            
                            VStack(spacing: 16) {
                                
                                // ── TARGET ITEM ───────────────────────
                                VStack(alignment: .leading, spacing: 8) {
                                    
                                    HStack {
                                        Text("TARGET ITEM")
                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                            .foregroundColor(.white.opacity(0.6))
                                        Spacer()
                                        if let sel = selectedItem {
                                            HStack(spacing: 4) {
                                                Image(systemName: "checkmark.circle.fill").font(.system(size: 10))
                                                Text(sel).font(.system(size: 10, design: .monospaced))
                                            }
                                            .foregroundColor(Color(red: 1.0, green: 0.8, blue: 0.0))
                                        }
                                    }
                                    
                                    // 搜索框 + ALL 按钮
                                    HStack(spacing: 0) {
                                        ZStack(alignment: .leading) {
                                            Rectangle().fill(Color(red: 0.12, green: 0.13, blue: 0.16))
                                            Rectangle().stroke(
                                                searchFocused
                                                    ? Color(red: 1.0, green: 0.8, blue: 0.0)
                                                    : Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.3),
                                                lineWidth: searchFocused ? 2 : 1
                                            )
                                            
                                            HStack(spacing: 10) {
                                                Image(systemName: "magnifyingglass")
                                                    .font(.system(size: 14))
                                                    .foregroundColor(searchFocused
                                                        ? Color(red: 1.0, green: 0.8, blue: 0.0)
                                                        : .white.opacity(0.35))
                                                
                                                ZStack(alignment: .leading) {
                                                    if showDropdown,
                                                       !searchText.isEmpty,
                                                       let first = suggestions.first,
                                                       first.matchType == .prefixMatch,
                                                       first.name.count > searchText.count {
                                                        Text(first.name)
                                                            .font(.system(size: 15))
                                                            .foregroundColor(.white.opacity(0.2))
                                                            .allowsHitTesting(false)
                                                    }
                                                    
                                                    TextField("", text: $searchText, prompt:
                                                        Text("搜索或选择物品...")
                                                            .foregroundColor(.white.opacity(0.28))
                                                    )
                                                    .font(.system(size: 15))
                                                    .foregroundColor(.white)
                                                    .focused($searchFocused)
                                                    .autocorrectionDisabled()
                                                    .onChange(of: searchFocused) { focused in
                                                        withAnimation(.easeInOut(duration: 0.18)) {
                                                            showDropdown = focused
                                                        }
                                                    }
                                                    .onChange(of: searchText) { _ in
                                                        if !showDropdown { showDropdown = true }
                                                    }
                                                    .onSubmit {
                                                        if let first = suggestions.first {
                                                            selectItem(first.name)
                                                        }
                                                    }
                                                }
                                                
                                                if !searchText.isEmpty {
                                                    Button {
                                                        withAnimation(.easeInOut(duration: 0.15)) {
                                                            searchText = ""
                                                            selectedItem = nil
                                                        }
                                                    } label: {
                                                        Image(systemName: "xmark.circle.fill")
                                                            .font(.system(size: 15))
                                                            .foregroundColor(.white.opacity(0.35))
                                                    }
                                                }
                                            }
                                            .padding(.horizontal, 12)
                                        }
                                        .frame(height: 50)
                                        
                                        Menu {
                                            ForEach(vm.recipes.keys.sorted(), id: \.self) { item in
                                                Button(item) { selectItem(item) }
                                            }
                                        } label: {
                                            ZStack {
                                                Rectangle().fill(Color(red: 0.08, green: 0.09, blue: 0.12))
                                                Rectangle().stroke(Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.3), lineWidth: 1)
                                                VStack(spacing: 3) {
                                                    Image(systemName: "line.3.horizontal.decrease")
                                                        .font(.system(size: 16))
                                                        .foregroundColor(Color(red: 1.0, green: 0.8, blue: 0.0))
                                                    Text("ALL")
                                                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                                                        .foregroundColor(Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.7))
                                                }
                                            }
                                            .frame(width: 52, height: 50)
                                        }
                                    }
                                    
                                    // ── 联想下拉列表 ──────────────────────
                                    if showDropdown {
                                        SuggestionDropdown(
                                            suggestions: suggestions,
                                            searchText: searchText,
                                            selectedItem: selectedItem,
                                            historyMgr: historyMgr,
                                            onSelect: selectItem,
                                            onDeleteHistory: { historyMgr.remove($0) },
                                            onClearHistory: { historyMgr.clear() }
                                        )
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                
                                // ── 数量控制 ─────────────────────────────
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("QUANTITY")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.6))
                                    
                                    HStack(spacing: 0) {
                                        Button {
                                            if amount > 1 { withAnimation(.spring(response: 0.3)) { amount -= 1 } }
                                        } label: {
                                            ZStack {
                                                Rectangle().fill(Color(red: 0.12, green: 0.13, blue: 0.16)).frame(width: 50, height: 50)
                                                Image(systemName: "minus").font(.system(size: 18, weight: .bold))
                                                    .foregroundColor(amount > 1 ? Color(red: 1.0, green: 0.8, blue: 0.0) : .white.opacity(0.2))
                                            }
                                        }
                                        .disabled(amount <= 1)
                                        
                                        Spacer()
                                        Text("\(amount)")
                                            .font(.system(size: 32, weight: .bold, design: .monospaced))
                                            .foregroundColor(Color(red: 1.0, green: 0.8, blue: 0.0))
                                            .frame(minWidth: 80)
                                            .animation(.spring(response: 0.3), value: amount)
                                        Spacer()
                                        
                                        Button {
                                            if amount < 100 { withAnimation(.spring(response: 0.3)) { amount += 1 } }
                                        } label: {
                                            ZStack {
                                                Rectangle().fill(Color(red: 0.12, green: 0.13, blue: 0.16)).frame(width: 50, height: 50)
                                                Image(systemName: "plus").font(.system(size: 18, weight: .bold))
                                                    .foregroundColor(amount < 100 ? Color(red: 1.0, green: 0.8, blue: 0.0) : .white.opacity(0.2))
                                            }
                                        }
                                        .disabled(amount >= 100)
                                    }
                                    .frame(height: 50)
                                    .background(Rectangle().stroke(Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.3), lineWidth: 1))
                                }
                                .frame(maxWidth: .infinity)
                                
                                // ── 执行按钮 ──────────────────────────────
                                VStack(spacing: 8) {
                                    Button {
                                        if let item = selectedItem {
                                            showEmptyHint = false
                                            dismissDropdown()
                                            withAnimation(.spring(response: 0.4)) {
                                                vm.buildTree(target: item, amount: amount)
                                                showTree = true
                                            }
                                        } else {
                                            withAnimation(.spring(response: 0.3)) {
                                                showEmptyHint = true
                                            }
                                        }
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: "play.fill")
                                            Text("查看配方").font(.system(size: 14, weight: .bold, design: .monospaced))
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(ZStack {
                                            Rectangle().fill(selectedItem == nil
                                                ? Color.white.opacity(0.1)
                                                : Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.2))
                                            Rectangle().stroke(selectedItem == nil
                                                ? Color.white.opacity(0.2)
                                                : Color(red: 1.0, green: 0.8, blue: 0.0), lineWidth: 2)
                                        })
                                        .foregroundColor(selectedItem == nil
                                            ? .white.opacity(0.3)
                                            : Color(red: 1.0, green: 0.8, blue: 0.0))
                                    }
                                    .frame(maxWidth: .infinity)

                                    if showEmptyHint {
                                        HStack(spacing: 6) {
                                            Image(systemName: "exclamationmark.circle")
                                                .font(.system(size: 11))
                                            Text("请先搜索或选择一个配方")
                                                .font(.system(size: 12, design: .monospaced))
                                        }
                                        .foregroundColor(Color(red: 0.9, green: 0.5, blue: 0.2))
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                    }
                                }
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 20)
                        }
                        .background(
                            Rectangle()
                                .fill(Color(red: 0.12, green: 0.13, blue: 0.16))
                                .overlay(Rectangle().stroke(
                                    LinearGradient(
                                        colors: [Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.3),
                                                 Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.05)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing),
                                    lineWidth: 1))
                        )
                        .padding(.horizontal)
                        .padding(.top, 10)
                        
                        // ── 配方树结果 ─────────────────────────────────
                        if showTree, let root = vm.rootNode {
                            VStack(spacing: 16) {
                                VStack(spacing: 0) {
                                    HStack {
                                        Rectangle().fill(Color(red: 1.0, green: 0.8, blue: 0.0)).frame(width: 3, height: 16)
                                        Text("分析结果").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(.white.opacity(0.8))
                                        Spacer()
                                    }
                                    .padding(.horizontal, 16).padding(.vertical, 12)
                                    .background(Color(red: 0.08, green: 0.09, blue: 0.12))
                                    
                                    HStack(spacing: 0) {
                                        EndFieldStatCard(icon: "clock.fill", title: "TIME", value: "\(root.totalTime)", unit: "SEC", color: Color(red: 0.9, green: 0.5, blue: 0.2))
                                        Divider().overlay(Color.white.opacity(0.1))
                                        EndFieldStatCard(icon: "gearshape.2.fill", title: "BATCH", value: "\(root.batches)", unit: "CNT", color: Color(red: 0.6, green: 0.4, blue: 0.9))
                                        Divider().overlay(Color.white.opacity(0.1))
                                        EndFieldStatCard(icon: "arrow.triangle.branch", title: "STEPS", value: "\(countNodes(root))", unit: "CNT", color: Color(red: 0.4, green: 0.8, blue: 0.2))
                                    }
                                    .frame(height: 80)
                                    .background(Color(red: 0.12, green: 0.13, blue: 0.16))
                                }
                                .background(Rectangle().stroke(Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.2), lineWidth: 1))
                                .padding(.horizontal).padding(.top, 16)
                                
                                VStack(spacing: 0) {
                                    HStack {
                                        Rectangle().fill(Color(red: 1.0, green: 0.8, blue: 0.0)).frame(width: 3, height: 16)
                                        Text("配方树").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(.white.opacity(0.8))
                                        Spacer()
                                        Text("PREVIEW").font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundColor(.white.opacity(0.4))
                                    }
                                    .padding(.horizontal, 16).padding(.vertical, 12)
                                    .background(Color(red: 0.08, green: 0.09, blue: 0.12))
                                    
                                    ZStack {
                                        ThumbnailPreview(root: root).frame(height: 300).background(Color(red: 0.12, green: 0.13, blue: 0.16))
                                        VStack {
                                            Spacer()
                                            Button { showDetailView = true } label: {
                                                HStack(spacing: 6) {
                                                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                                                    Text("VIEW FULL TREE").font(.system(size: 12, weight: .bold, design: .monospaced))
                                                }
                                                .padding(.horizontal, 20).padding(.vertical, 12)
                                                .background(ZStack {
                                                    Rectangle().fill(Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.2))
                                                    Rectangle().stroke(Color(red: 1.0, green: 0.8, blue: 0.0), lineWidth: 2)
                                                })
                                                .foregroundColor(Color(red: 1.0, green: 0.8, blue: 0.0))
                                            }
                                            .padding(.bottom, 20)
                                        }
                                    }
                                    .onTapGesture { showDetailView = true }
                                }
                                .background(Rectangle().stroke(Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.2), lineWidth: 1))
                                .padding(.horizontal)
                            }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            
                        } else if showTree {
                            VStack(spacing: 16) {
                                Image(systemName: "exclamationmark.triangle").font(.system(size: 60)).foregroundColor(.red.opacity(0.5))
                                Text("ERROR: RECIPE NOT FOUND").font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundColor(.red.opacity(0.8))
                                Text("未找到配方数据").font(.subheadline).foregroundColor(.white.opacity(0.6))
                            }
                            .frame(maxHeight: .infinity).padding(.top, 60)
                        }
                        
                        Spacer(minLength: 40)
                    }
                    .frame(maxWidth: 940)
                    .frame(maxWidth: .infinity)
                }
                .onTapGesture { dismissDropdown() }
                
                // ── 免责声明弹窗覆盖层 ────────────────────────────
                if showDisclaimer {
                    RecipeDisclaimerOverlay {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showDisclaimer = false
                            disclaimerSeen = true
                        }
                    }
                    .transition(.opacity)
                    .zIndex(10)
                }
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text.magnifyingglass").foregroundColor(Color(red: 1.0, green: 0.8, blue: 0.0))
                        Text("RECIPE ANALYSIS").font(.system(size: 16, weight: .bold, design: .monospaced)).foregroundColor(.white)
                    }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color(red: 0.08, green: 0.09, blue: 0.12), for: .navigationBar)
            .sheet(isPresented: $showDetailView) {
                if let root = vm.rootNode { RecipeDetailView(root: root) }
            }
            .onAppear {
                // 首次进入时弹出免责声明
                if !disclaimerSeen {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showDisclaimer = true
                    }
                }
            }
        }
    }
    
    // MARK: - 辅助方法
    
    private func selectItem(_ item: String) {
        withAnimation(.easeInOut(duration: 0.15)) {
            selectedItem = item
            searchText = item
            showDropdown = false
            searchFocused = false
            showEmptyHint = false
        }
        historyMgr.add(item)
    }
    
    private func dismissDropdown() {
        withAnimation(.easeInOut(duration: 0.18)) {
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
    
    private let accent = Color(red: 1.0, green: 0.8, blue: 0.0)
    
    var body: some View {
        ZStack {
            // 半透明遮罩
            Color.black.opacity(0.6)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                
                // 顶部标题栏
                HStack(spacing: 10) {
                    Rectangle()
                        .fill(accent)
                        .frame(width: 3, height: 20)
                    
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(accent)
                    
                    Text("DATA NOTICE")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(accent)
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(Color(red: 0.08, green: 0.09, blue: 0.12))
                
                // 分隔线
                Rectangle()
                    .fill(accent.opacity(0.3))
                    .frame(height: 1)
                
                // 正文内容
                VStack(alignment: .leading, spacing: 16) {
                    
                    Text("时间数据说明")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        DisclaimerRow(
                            icon: "arrow.triangle.branch",
                            text: "本功能展示的生产时间基于单条串行链路计算，即从原材料到成品的最长路径耗时。"
                        )
                        
                        DisclaimerRow(
                            icon: "minus.circle",
                            text: "计算结果不包含采矿、种植等原材料采集环节的时间，亦未考虑传送带运输延迟、建筑数量限制、产线调度等实际因素。"
                        )
                        
                        DisclaimerRow(
                            icon: "info.circle",
                            text: "展示数据仅供规划参考，实际生产效率以游戏内表现为准。"
                        )
                    }
                }
                .padding(20)
                .background(Color(red: 0.12, green: 0.13, blue: 0.16))
                
                // 分隔线
                Rectangle()
                    .fill(accent.opacity(0.3))
                    .frame(height: 1)
                
                // 确认按钮
                Button(action: onConfirm) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                        Text("我已了解")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .foregroundColor(accent)
                    .background(Color(red: 0.08, green: 0.09, blue: 0.12))
                }
            }
            .background(Color(red: 0.12, green: 0.13, blue: 0.16))
            .overlay(
                Rectangle()
                    .stroke(accent.opacity(0.4), lineWidth: 1)
            )
            .frame(maxWidth: 560)
            .padding(.horizontal, 32)
        }
    }
}

// MARK: - 免责声明条目

struct DisclaimerRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.7))
                .frame(width: 16, height: 20)
            
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.75))
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
    
    private let accent = Color(red: 1.0, green: 0.8, blue: 0.0)
    
    private var groups: [(label: String, icon: String, items: [SuggestionItem])] {
        let history  = suggestions.filter { $0.matchType == .history }
        let prefix   = suggestions.filter { $0.matchType == .prefixMatch }
        let contains = suggestions.filter { $0.matchType == .containsMatch }
        var g: [(String, String, [SuggestionItem])] = []
        if !history.isEmpty  { g.append(("最近搜索",    "clock.arrow.circlepath", history))  }
        if !prefix.isEmpty   { g.append(("BEST MATCH", "target",                 prefix))   }
        if !contains.isEmpty { g.append(("CONTAINS",   "text.magnifyingglass",   contains)) }
        return g
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if suggestions.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: searchText.isEmpty ? "clock" : "magnifyingglass")
                        .font(.system(size: 12)).foregroundColor(.white.opacity(0.25))
                    Text(searchText.isEmpty ? "暂无搜索历史" : "未找到匹配物品")
                        .font(.system(size: 13, design: .monospaced)).foregroundColor(.white.opacity(0.25))
                    Spacer()
                }
                .padding(.horizontal, 14).padding(.vertical, 14)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(groups.enumerated()), id: \.offset) { gi, group in
                            
                            HStack(spacing: 6) {
                                Image(systemName: group.icon).font(.system(size: 9, weight: .bold))
                                Text(group.label).font(.system(size: 9, weight: .bold, design: .monospaced))
                                Spacer()
                                if group.label == "最近搜索" {
                                    Button { withAnimation { onClearHistory() } } label: {
                                        Text("清除").font(.system(size: 9, design: .monospaced)).foregroundColor(accent.opacity(0.6))
                                    }
                                }
                            }
                            .foregroundColor(.white.opacity(0.35))
                            .padding(.horizontal, 12)
                            .padding(.top, gi == 0 ? 10 : 6)
                            .padding(.bottom, 4)
                            
                            ForEach(group.items) { item in
                                let isSelected = item.name == selectedItem
                                
                                HStack(spacing: 10) {
                                    Image(systemName: item.matchType == .history ? "clock" : "arrow.right")
                                        .font(.system(size: 11))
                                        .foregroundColor(isSelected ? accent : .white.opacity(0.25))
                                        .frame(width: 14)
                                    
                                    HighlightedText(
                                        text: item.name,
                                        highlight: searchText,
                                        baseColor: isSelected ? accent : .white,
                                        highlightColor: accent
                                    )
                                    .font(.system(size: 14))
                                    
                                    Spacer()
                                    
                                    HStack(spacing: 8) {
                                        if isSelected {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundColor(accent)
                                        }
                                        if item.matchType == .history {
                                            Button { withAnimation { onDeleteHistory(item.name) } } label: {
                                                Image(systemName: "xmark")
                                                    .font(.system(size: 10))
                                                    .foregroundColor(.white.opacity(0.3))
                                                    .padding(4)
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, 12).padding(.vertical, 10)
                                .background(isSelected ? accent.opacity(0.08) : Color.clear)
                                .contentShape(Rectangle())
                                .onTapGesture { onSelect(item.name) }
                                
                                Rectangle().fill(Color.white.opacity(0.04)).frame(height: 1).padding(.leading, 36)
                            }
                            
                            if gi < groups.count - 1 {
                                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                                    .padding(.horizontal, 12).padding(.vertical, 4)
                            }
                        }
                        Color.clear.frame(height: 6)
                    }
                }
                .frame(maxHeight: 240)
            }
        }
        .background(Color(red: 0.10, green: 0.11, blue: 0.14))
        .overlay(Rectangle().stroke(accent.opacity(0.22), lineWidth: 1))
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
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 20)).foregroundColor(color)
            Text(value).font(.system(size: 24, weight: .bold, design: .monospaced)).foregroundColor(color)
            Text(title).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(.white.opacity(0.4))
            Text(unit).font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundColor(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
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
            let s = CGPoint(x: child.positionX * xS + nW/2, y: CGFloat(child.level) * yS + nH/2)
            let e = CGPoint(x: node.positionX  * xS + nW/2, y: CGFloat(node.level)  * yS - nH/2)
            var p = Path(); p.move(to: s)
            p.addCurve(to: e, control1: CGPoint(x: s.x, y: s.y+(e.y-s.y)*0.5), control2: CGPoint(x: e.x, y: s.y+(e.y-s.y)*0.5))
            ctx.stroke(p, with: .color(Color(red:1,green:0.8,blue:0).opacity(0.3)), lineWidth: 1.5)
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
        let c = node.recipe == nil ? Color(red: 0.9, green: 0.5, blue: 0.2) : Color(red: 1.0, green: 0.8, blue: 0.0)
        return VStack(spacing: 2) {
            Text(node.name).font(.system(size: 9, weight: .semibold)).foregroundColor(.white).lineLimit(1)
            Text("x\(node.amount)").font(.system(size: 8, design: .monospaced)).foregroundColor(.white.opacity(0.6))
        }
        .frame(width: nodeWidth, height: nodeHeight)
        .background(ZStack {
            Rectangle().fill(c.opacity(0.2))
            Rectangle().stroke(c.opacity(0.5), lineWidth: 1)
        })
    }
}
