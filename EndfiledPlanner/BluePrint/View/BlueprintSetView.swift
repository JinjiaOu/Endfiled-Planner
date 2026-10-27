// Created by Jinjia Ou on 2/21/26.

import SwiftUI

struct BlueprintSetView: View {
    @StateObject private var viewModel = BlueprintSetViewModel()
    @State private var selectedSet: BlueprintSet?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var listColumns: [GridItem] {
        horizontalSizeClass == .regular && !dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.adaptive(minimum: 320), spacing: AppSpacing.md, alignment: .top)]
            : [GridItem(.flexible())]
    }

    // 免责声明相关状态
    @AppStorage("hasAcceptedBlueprintDisclaimer") private var hasAccepted = false
    @State private var showDisclaimer = false
    
    var body: some View {
        ZStack {
            AppTopographicBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    BlueprintSetBanner()
                    BlueprintSetFilterBar(authorSearch: $viewModel.authorSearch,
                                          selectedRegion: $viewModel.selectedRegion,
                                          availableRegions: viewModel.availableRegions)
                    if viewModel.isLoading {
                        BlueprintSetLoadingView()
                    } else if let error = viewModel.errorMessage {
                        BlueprintSetErrorView(message: error) { viewModel.loadBlueprintSets() }
                    } else if viewModel.filteredSets.isEmpty {
                        BlueprintSetEmptyView(hasSets: !viewModel.blueprintSets.isEmpty)
                    } else {
                        HStack {
                            Text(String(localized: "蓝图集")).font(AppTypography.sectionTitle)
                            Spacer()
                            Text(String(localized: "\(viewModel.filteredSets.count) 个结果"))
                                .font(AppTypography.numeric).foregroundStyle(AppColors.secondaryText)
                        }
                        LazyVGrid(columns: listColumns, alignment: .leading, spacing: AppSpacing.md) {
                            ForEach(viewModel.filteredSets) { set in
                                Button { selectedSet = set } label: {
                                    BlueprintSetCard(blueprintSet: set)
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint(String(localized: "打开蓝图集，查看说明与复制分享码"))
                            }
                        }
                    }
                }
                .padding(AppSpacing.md)
                .frame(maxWidth: 1120, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            if showDisclaimer {
                BlueprintDisclaimerView(isPresented: $showDisclaimer)
                    .zIndex(999)
            }
        }
        .foregroundStyle(AppColors.primaryText)
        .navigationTitle(String(localized: "社区蓝图"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { viewModel.refreshBlueprintSets() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel(String(localized: "刷新蓝图集"))
            }
        }
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(AppColors.background, for: .navigationBar)
        .tint(AppColors.accent)
        .sheet(item: $selectedSet) { set in
            BlueprintSetDetailView(blueprintSet: set)
        }
        .onAppear {
            // 首次进入时显示免责声明
            if !hasAccepted {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showDisclaimer = true
                    }
                }
            }
            
            if viewModel.blueprintSets.isEmpty {
                viewModel.loadBlueprintSets()
            }
        }
    }

}

struct BlueprintSetBanner: View {
    var body: some View {
        AppPageHeader(title: String(localized: "发现可复用的产线"), subtitle: String(localized: "按作者与地图查找蓝图集，查看说明并复制分享码。"))
    }
}

struct BlueprintSetFilterBar: View {
    @Binding var authorSearch: String
    @Binding var selectedRegion: String?
    let availableRegions: [String]
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        AppSurface {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                AppSectionHeader(title: String(localized: "查找蓝图"))
                if horizontalSizeClass == .regular && !dynamicTypeSize.isAccessibilitySize {
                    HStack(spacing: AppSpacing.sm) {
                        AppSearchField(text: $authorSearch, prompt: String(localized: "搜索作者"))
                        BlueprintSetRegionMenu(selection: $selectedRegion, options: availableRegions)
                            .frame(width: 220)
                    }
                } else {
                    AppSearchField(text: $authorSearch, prompt: String(localized: "搜索作者"))
                    BlueprintSetRegionMenu(selection: $selectedRegion, options: availableRegions)
                }
            }
        }
    }
}

struct BlueprintSetRegionMenu: View {
    @Binding var selection: String?
    let options: [String]

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button { selection = option == "全部" ? nil : option } label: {
                    if option == (selection ?? "全部") { Label(DisplayName.region(option), systemImage: "checkmark") }
                    else { Text(verbatim: DisplayName.region(option)) }
                }
            }
        } label: {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "map").foregroundStyle(AppColors.accent)
                Text(selection.map(DisplayName.region) ?? String(localized: "全部地图")).font(AppTypography.rowTitle)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: AppSpacing.xs)
                Image(systemName: "chevron.down").font(AppTypography.caption)
            }
            .foregroundStyle(AppColors.primaryText)
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.xs)
            .frame(minHeight: AppSize.rowMinimum)
            .background(AppColors.background, in: RoundedRectangle(cornerRadius: AppRadius.control))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.control).strokeBorder(AppColors.controlBorder, lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityLabel(String(localized: "地图筛选"))
        .accessibilityValue(selection.map(DisplayName.region) ?? String(localized: "全部地图"))
    }
}

struct BlueprintSetLoadingView: View {
    var body: some View {
        AppSurface { AppLoadingState(title: String(localized: "正在加载蓝图集")) }
    }
}

struct BlueprintSetErrorView: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        AppSurface {
            AppContentState(title: String(localized: "蓝图集加载失败"), message: message,
                            systemImage: "exclamationmark.triangle", tone: .error) {
                Button(String(localized: "重新加载"), action: retry).buttonStyle(AppActionStyle())
            }
        }
    }
}

struct BlueprintSetEmptyView: View {
    let hasSets: Bool
    var body: some View {
        AppSurface {
            AppContentState(title: hasSets ? String(localized: "没有匹配的蓝图集") : String(localized: "暂无蓝图集"),
                            message: hasSets ? String(localized: "尝试调整作者关键词或地图筛选。") : String(localized: "可通过右上角刷新重新获取数据。"),
                            systemImage: hasSets ? "magnifyingglass" : "square.stack")
        }
    }
}

#Preview { NavigationStack { BlueprintSetView() } }
