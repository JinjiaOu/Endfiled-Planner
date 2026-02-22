//
//  ContentView.swift
//  EndfiledPlanner
//
//  Created by Jinjia Ou on 2/14/26.
//

import SwiftUI

struct ContentView: View {
    
    var body: some View {
        HomeView()
    }
}

// 主页视图 - Endfield 风格
struct HomeView: View {
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 深色背景
                Color(red: 0.08, green: 0.09, blue: 0.12)
                    .ignoresSafeArea()
                
                // 网格图案背景
                GeometryReader { geometry in
                    Canvas { context, size in
                        let spacing: CGFloat = 30
                        
                        // 绘制网格
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
                            with: .color(Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.1)),
                            lineWidth: 0.5
                        )
                    }
                }
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        
                        // 终末地风格横幅
                        EndFieldBanner()
                            .padding(.horizontal)
                            .padding(.top, 20)
                        
                        // 功能卡片区域
                        VStack(spacing: 16) {
                            
                            HStack {
                                Rectangle()
                                    .fill(Color(red: 1.0, green: 0.8, blue: 0.0))
                                    .frame(width: 3, height: 20)
                                
                                Text("系统功能")
                                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                                    .textCase(.uppercase)
                                
                                Spacer()
                            }
                            .padding(.horizontal)
                            
                            // 配方查询卡片
                            NavigationLink(destination: SearchView()) {
                                EndFieldFeatureCard(
                                    icon: "doc.text.magnifyingglass",
                                    title: "配方分析系统",
                                    description: "RECIPE ANALYSIS",
                                    subtitle: "生产链可视化分析",
                                    color: Color(red: 1.0, green: 0.8, blue: 0.0),
                                    status: "ONLINE"
                                )
                            }
                            .padding(.horizontal)
                            
                            // 蓝图码管理卡片
                            NavigationLink(destination: BlueprintSetView()) {
                                EndFieldFeatureCard(
                                    icon: "doc.text.fill",
                                    title: "蓝图码管理系统",
                                    description: "BLUEPRINT MANAGER",
                                    subtitle: "蓝图码存储与分享",
                                    color: Color(red: 0.2, green: 0.6, blue: 0.9),
                                    status: "ONLINE"
                                )
                            }
                            .padding(.horizontal)
                            // 资源计算卡片
                            NavigationLink(destination: ResourceCalculatorView()) {
                                EndFieldFeatureCard(
                                    icon: "chart.bar.fill",
                                    title: "资源计算引擎",
                                    description: "RESOURCE CALCULATOR",
                                    subtitle: "原材料需求统计",
                                    color: Color(red: 0.4, green: 0.8, blue: 0.2),
                                    status: "DEVELOPING"
                                )
                            }
                            .opacity(0.5)
                            .padding(.horizontal)
                            
                            // 生产优化卡片
                            NavigationLink(destination: ProductionOptimizerView()) {
                                EndFieldFeatureCard(
                                    icon: "cpu.fill",
                                    title: "生产优化模块",
                                    description: "PRODUCTION OPTIMIZER",
                                    subtitle: "效率与布局优化",
                                    color: Color(red: 0.9, green: 0.5, blue: 0.2),
                                    status: "DEVELOPING"
                                )
                            }
                            .opacity(0.5)
                            .padding(.horizontal)
                        }
                        
                        // 数据统计面板
                        EndFieldStatsView()
                            .padding(.horizontal)
                            .padding(.top, 8)
                        
                        Spacer(minLength: 20)
                    }
                }
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Image(systemName: "gear.circle.fill")
                            .foregroundColor(Color(red: 1.0, green: 0.8, blue: 0.0))
                        
                        Text("ENDFIELD PLANNER")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(Color(red: 1.0, green: 0.8, blue: 0.0))
                            .font(.system(size: 20))
                    }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color(red: 0.08, green: 0.09, blue: 0.12), for: .navigationBar)
        }
    }
}

// MARK: - 主页组件

// 终末地风格横幅
struct EndFieldBanner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            
            // 顶部装饰条
            HStack(spacing: 4) {
                Rectangle()
                    .fill(Color(red: 1.0, green: 0.8, blue: 0.0))
                    .frame(width: 40, height: 2)
                
                Circle()
                    .fill(Color(red: 1.0, green: 0.8, blue: 0.0))
                    .frame(width: 4, height: 4)
                
                Spacer()
            }
            .padding(.bottom, 12)
            
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("SYSTEM ONLINE")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(red: 1.0, green: 0.8, blue: 0.0))
                    
                    Text("生产规划系统")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("Production Planning Terminal")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                }
                
                Spacer()
                
                // 状态指示器
                VStack(spacing: 6) {
                    Circle()
                        .fill(Color(red: 1.0, green: 0.8, blue: 0.0))
                        .frame(width: 8, height: 8)
                        .overlay(
                            Circle()
                                .stroke(Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.3), lineWidth: 4)
                                .scaleEffect(1.5)
                        )
                    
                    Text("READY")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(red: 1.0, green: 0.8, blue: 0.0))
                }
            }
            .padding(20)
        }
        .background(
            ZStack {
                // 主背景
                Rectangle()
                    .fill(Color(red: 0.12, green: 0.13, blue: 0.16))
                
                // 边框
                Rectangle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.5),
                                Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.1)
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

// 终末地风格功能卡片
struct EndFieldFeatureCard: View {
    let icon: String
    let title: String
    let description: String
    let subtitle: String
    let color: Color
    let status: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            
            // 顶部状态栏
            HStack {
                Text(status)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(status == "ONLINE" ? color : .white.opacity(0.4))
                
                Spacer()
                
                if status == "ONLINE" {
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(red: 0.08, green: 0.09, blue: 0.12))
            
            // 主内容区
            HStack(spacing: 16) {
                
                // 图标区域
                ZStack {
                    Circle()
                        .stroke(color.opacity(0.3), lineWidth: 2)
                        .frame(width: 60, height: 60)
                    
                    Circle()
                        .fill(color.opacity(0.1))
                        .frame(width: 54, height: 54)
                    
                    Image(systemName: icon)
                        .font(.system(size: 24))
                        .foregroundColor(color)
                }
                
                // 文字信息
                VStack(alignment: .leading, spacing: 4) {
                    Text(description)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(color.opacity(0.8))
                    
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                }
                
                Spacer()
                
                // 箭头
                if status == "ONLINE" {
                    Image(systemName: "chevron.right")
                        .foregroundColor(color.opacity(0.6))
                        .font(.system(size: 14, weight: .bold))
                }
            }
            .padding(16)
            .background(Color(red: 0.12, green: 0.13, blue: 0.16))
        }
        .clipShape(RoundedRectangle(cornerRadius: 0))
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(
                    LinearGradient(
                        colors: [color.opacity(0.3), color.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
}

// 终末地风格统计视图
struct EndFieldStatsView: View {
    
    @StateObject var vm = RecipeViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            
            // 标题栏
            HStack {
                Rectangle()
                    .fill(Color(red: 1.0, green: 0.8, blue: 0.0))
                    .frame(width: 3, height: 16)
                
                Text("DATABASE STATUS")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(red: 0.08, green: 0.09, blue: 0.12))
            
            // 统计数据
            HStack(spacing: 0) {
                
                EndFieldStatBox(
                    title: "RECIPES",
                    value: "\(totalRecipes())",
                    unit: "TOTAL",
                    color: Color(red: 1.0, green: 0.8, blue: 0.0)
                )
                
                Divider()
                    .overlay(Color.white.opacity(0.1))
                
                EndFieldStatBox(
                    title: "ITEMS",
                    value: "\(vm.recipes.keys.count)",
                    unit: "TYPES",
                    color: Color(red: 0.4, green: 0.8, blue: 0.2)
                )
                
                Divider()
                    .overlay(Color.white.opacity(0.1))
                
                EndFieldStatBox(
                    title: "MACHINES",
                    value: "\(uniqueMachines())",
                    unit: "MODELS",
                    color: Color(red: 0.9, green: 0.5, blue: 0.2)
                )
            }
            .frame(height: 80)
            .background(Color(red: 0.12, green: 0.13, blue: 0.16))
        }
        .clipShape(RoundedRectangle(cornerRadius: 0))
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.2), lineWidth: 1)
        )
    }
    
    private func totalRecipes() -> Int {
        vm.recipes.values.reduce(0) { $0 + $1.count }
    }
    
    private func uniqueMachines() -> Int {
        let machines = Set(
            vm.recipes.values.flatMap { recipes in
                recipes.compactMap { $0.machine }
            }
        )
        return machines.count
    }
}

// 终末地风格统计盒子
struct EndFieldStatBox: View {
    let title: String
    let value: String
    let unit: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            
            Text(title)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
            
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .foregroundColor(color)
            
            Text(unit)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
