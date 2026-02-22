//
//  BlueprintView.swift
//  EndfiledPlanner
//
//  Created by Jinjia Ou on 2/14/26.
//

import SwiftUI

struct BlueprintView: View {
    
    @StateObject private var viewModel = BlueprintViewModel()
    @State private var selectedBlueprint: Blueprint?
    @State private var showFilters = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 深色背景
                Color(red: 0.08, green: 0.09, blue: 0.12)
                    .ignoresSafeArea()
                
                // 网格背景
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
                    context.stroke(
                        path,
                        with: .color(Color(red: 0.2, green: 0.6, blue: 0.9).opacity(0.1)),
                        lineWidth: 0.5
                    )
                }
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    
                    // 页面横幅
                    BlueprintBanner()
                        .padding(.horizontal)
                        .padding(.top, 10)
                    
                    // 搜索和筛选栏
                    SearchAndFilterBar(
                        searchText: $viewModel.searchText,
                        selectedRegion: $viewModel.selectedRegion,
                        showFilters: $showFilters,
                        availableRegions: viewModel.availableRegions
                    )
                    .padding(.horizontal)
                    .padding(.top, 16)
                    
                    // 结果统计
                    if !viewModel.isLoading && !viewModel.filteredBlueprints.isEmpty {
                        HStack {
                            Text("找到 \(viewModel.filteredBlueprints.count) 个蓝图")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.6))
                            
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.top, 12)
                    }
                    
                    // 内容区域
                    if viewModel.isLoading {
                        LoadingView()
                    } else if let error = viewModel.errorMessage {
                        ErrorView(message: error) {
                            viewModel.loadBlueprints()
                        }
                    } else if viewModel.filteredBlueprints.isEmpty {
                        EmptyStateView(hasBlueprints: !viewModel.blueprints.isEmpty)
                    } else {
                        BlueprintListView(
                            blueprints: viewModel.filteredBlueprints,
                            selectedBlueprint: $selectedBlueprint
                        )
                    }
                }
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text.fill")
                            .foregroundColor(Color(red: 0.2, green: 0.6, blue: 0.9))
                        
                        Text("BLUEPRINT MANAGER")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        viewModel.refreshBlueprints()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(Color(red: 0.2, green: 0.6, blue: 0.9))
                    }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color(red: 0.08, green: 0.09, blue: 0.12), for: .navigationBar)
            .sheet(item: $selectedBlueprint) { blueprint in
                BlueprintDetailView(blueprint: blueprint)
            }
            .onAppear {
                if viewModel.blueprints.isEmpty {
                    viewModel.loadBlueprints()
                }
            }
        }
    }
}

// MARK: - 子视图组件

struct BlueprintBanner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Rectangle()
                    .fill(Color(red: 0.2, green: 0.6, blue: 0.9))
                    .frame(width: 40, height: 2)
                Circle()
                    .fill(Color(red: 0.2, green: 0.6, blue: 0.9))
                    .frame(width: 4, height: 4)
                Spacer()
            }
            .padding(.bottom, 12)
            
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("BLUEPRINT SHOWCASE")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(red: 0.2, green: 0.6, blue: 0.9))
                    
                    Text("蓝图展示系统")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("Community Blueprint Gallery")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                }
                
                Spacer()
                
                VStack(spacing: 6) {
                    Circle()
                        .fill(Color(red: 0.2, green: 0.6, blue: 0.9))
                        .frame(width: 8, height: 8)
                        .overlay(
                            Circle()
                                .stroke(Color(red: 0.2, green: 0.6, blue: 0.9).opacity(0.3), lineWidth: 4)
                                .scaleEffect(1.5)
                        )
                    
                    Text("ONLINE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(red: 0.2, green: 0.6, blue: 0.9))
                }
            }
            .padding(20)
        }
        .background(
            ZStack {
                Rectangle()
                    .fill(Color(red: 0.12, green: 0.13, blue: 0.16))
                Rectangle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(red: 0.2, green: 0.6, blue: 0.9).opacity(0.5),
                                Color(red: 0.2, green: 0.6, blue: 0.9).opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
    }
}

struct SearchAndFilterBar: View {
    @Binding var searchText: String
    @Binding var selectedRegion: String?
    @Binding var showFilters: Bool
    
    let availableRegions: [String]
    
    var body: some View {
        VStack(spacing: 12) {
            // 搜索框
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Color(red: 0.2, green: 0.6, blue: 0.9))
                
                TextField("搜索蓝图...", text: $searchText)
                    .foregroundColor(.white)
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
                
                Button {
                    withAnimation {
                        showFilters.toggle()
                    }
                } label: {
                    Image(systemName: showFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .foregroundColor(Color(red: 0.2, green: 0.6, blue: 0.9))
                }
            }
            .padding()
            .background(
                ZStack {
                    Rectangle()
                        .fill(Color(red: 0.12, green: 0.13, blue: 0.16))
                    Rectangle()
                        .stroke(Color(red: 0.2, green: 0.6, blue: 0.9).opacity(0.3), lineWidth: 1)
                }
            )
            
            // 筛选器
            if showFilters {
                FilterMenu(
                    title: "地区",
                    selection: $selectedRegion,
                    options: availableRegions
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
}

struct FilterMenu: View {
    let title: String
    @Binding var selection: String?
    let options: [String]
    
    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button(option) {
                    selection = option == "全部" ? nil : option
                }
            }
        } label: {
            HStack {
                Text(selection ?? title)
                    .font(.system(size: 13))
                    .foregroundColor(selection == nil ? .white.opacity(0.6) : .white)
                
                Spacer()
                
                Image(systemName: "chevron.down")
                    .font(.system(size: 10))
                    .foregroundColor(Color(red: 0.2, green: 0.6, blue: 0.9))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                ZStack {
                    Rectangle()
                        .fill(Color(red: 0.12, green: 0.13, blue: 0.16))
                    Rectangle()
                        .stroke(Color(red: 0.2, green: 0.6, blue: 0.9).opacity(0.3), lineWidth: 1)
                }
            )
        }
    }
}

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(Color(red: 0.2, green: 0.6, blue: 0.9))
            
            Text("LOADING BLUEPRINTS...")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(Color(red: 0.2, green: 0.6, blue: 0.9))
        }
        .frame(maxHeight: .infinity)
    }
}

struct ErrorView: View {
    let message: String
    let retry: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(.red.opacity(0.5))
            
            Text("ERROR")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(.red.opacity(0.8))
            
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
            
            Button {
                retry()
            } label: {
                Text("RETRY")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(red: 0.2, green: 0.6, blue: 0.9))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        ZStack {
                            Rectangle()
                                .fill(Color(red: 0.12, green: 0.13, blue: 0.16))
                            Rectangle()
                                .stroke(Color(red: 0.2, green: 0.6, blue: 0.9), lineWidth: 2)
                        }
                    )
            }
        }
        .frame(maxHeight: .infinity)
        .padding()
    }
}

struct EmptyStateView: View {
    let hasBlueprints: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: hasBlueprints ? "magnifyingglass" : "doc.text")
                .font(.system(size: 60))
                .foregroundColor(Color(red: 0.2, green: 0.6, blue: 0.9).opacity(0.5))
            
            Text(hasBlueprints ? "NO RESULTS" : "NO BLUEPRINTS")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(Color(red: 0.2, green: 0.6, blue: 0.9))
            
            Text(hasBlueprints ? "未找到匹配的蓝图" : "暂无蓝图数据")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxHeight: .infinity)
    }
}

struct BlueprintListView: View {
    let blueprints: [Blueprint]
    @Binding var selectedBlueprint: Blueprint?
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(blueprints) { blueprint in
                    BlueprintCard(blueprint: blueprint)
                        .onTapGesture {
                            selectedBlueprint = blueprint
                        }
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
    }
}

#Preview {
    BlueprintView()
}
