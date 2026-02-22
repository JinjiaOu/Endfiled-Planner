//
//  SearchView.swift
//  EndfiledPlanner
//
//  Created by Jinjia Ou on 2/14/26.
//

import SwiftUI

struct SearchView: View {
    
    @StateObject var vm = RecipeViewModel()
    @State private var selectedItem: String?
    @State private var amount: Int = 1
    @State private var showTree = false
    @State private var showDetailView = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 深色背景
                Color(red: 0.08, green: 0.09, blue: 0.12)
                    .ignoresSafeArea()
                
                // 网格背景
                GeometryReader { geometry in
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
                            with: .color(Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.1)),
                            lineWidth: 0.5
                        )
                    }
                }
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 0) {
                        
                        // 控制面板
                        VStack(spacing: 20) {
                            
                            // 标题区域
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 4) {
                                    Rectangle()
                                        .fill(Color(red: 1.0, green: 0.8, blue: 0.0))
                                        .frame(width: 30, height: 2)
                                    Circle()
                                        .fill(Color(red: 1.0, green: 0.8, blue: 0.0))
                                        .frame(width: 4, height: 4)
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
                            
                            // 选择器区域
                            VStack(spacing: 16) {
                                
                                // 物品选择
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("TARGET ITEM")
                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                            .foregroundColor(.white.opacity(0.6))
                                        
                                        Spacer()
                                    }
                                    
                                    Menu {
                                        ForEach(vm.recipes.keys.sorted(), id: \.self) { item in
                                            Button(item) {
                                                selectedItem = item
                                            }
                                        }
                                    } label: {
                                        HStack {
                                            Text(selectedItem ?? "请选择物品")
                                                .foregroundColor(selectedItem == nil ? .white.opacity(0.4) : .white)
                                            Spacer()
                                            Image(systemName: "chevron.down")
                                                .foregroundColor(Color(red: 1.0, green: 0.8, blue: 0.0))
                                        }
                                        .padding()
                                        .background(
                                            ZStack {
                                                Rectangle()
                                                    .fill(Color(red: 0.12, green: 0.13, blue: 0.16))
                                                Rectangle()
                                                    .stroke(Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.3), lineWidth: 1)
                                            }
                                        )
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                
                                // 数量控制
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("QUANTITY")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.6))
                                    
                                    HStack(spacing: 0) {
                                        // 减少按钮
                                        Button {
                                            if amount > 1 {
                                                withAnimation(.spring(response: 0.3)) {
                                                    amount -= 1
                                                }
                                            }
                                        } label: {
                                            ZStack {
                                                Rectangle()
                                                    .fill(Color(red: 0.12, green: 0.13, blue: 0.16))
                                                    .frame(width: 50, height: 50)
                                                
                                                Image(systemName: "minus")
                                                    .font(.system(size: 18, weight: .bold))
                                                    .foregroundColor(amount > 1 ? Color(red: 1.0, green: 0.8, blue: 0.0) : .white.opacity(0.2))
                                            }
                                        }
                                        .disabled(amount <= 1)
                                        
                                        Spacer()
                                        
                                        // 数量显示
                                        Text("\(amount)")
                                            .font(.system(size: 32, weight: .bold, design: .monospaced))
                                            .foregroundColor(Color(red: 1.0, green: 0.8, blue: 0.0))
                                            .frame(minWidth: 80)
                                            .animation(.spring(response: 0.3), value: amount)
                                        
                                        Spacer()
                                        
                                        // 增加按钮
                                        Button {
                                            if amount < 100 {
                                                withAnimation(.spring(response: 0.3)) {
                                                    amount += 1
                                                }
                                            }
                                        } label: {
                                            ZStack {
                                                Rectangle()
                                                    .fill(Color(red: 0.12, green: 0.13, blue: 0.16))
                                                    .frame(width: 50, height: 50)
                                                
                                                Image(systemName: "plus")
                                                    .font(.system(size: 18, weight: .bold))
                                                    .foregroundColor(amount < 100 ? Color(red: 1.0, green: 0.8, blue: 0.0) : .white.opacity(0.2))
                                            }
                                        }
                                        .disabled(amount >= 100)
                                    }
                                    .frame(height: 50)
                                    .background(
                                        Rectangle()
                                            .stroke(Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.3), lineWidth: 1)
                                    )
                                }
                                .frame(maxWidth: .infinity)
                                
                                // 执行按钮
                                Button {
                                    if let item = selectedItem {
                                        withAnimation(.spring(response: 0.4)) {
                                            vm.buildTree(target: item, amount: amount)
                                            showTree = true
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "play.fill")
                                        Text("EXECUTE ANALYSIS")
                                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(
                                        ZStack {
                                            Rectangle()
                                                .fill(
                                                    selectedItem == nil
                                                        ? Color.white.opacity(0.1)
                                                        : Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.2)
                                                )
                                            
                                            Rectangle()
                                                .stroke(
                                                    selectedItem == nil
                                                        ? Color.white.opacity(0.2)
                                                        : Color(red: 1.0, green: 0.8, blue: 0.0),
                                                    lineWidth: 2
                                                )
                                        }
                                    )
                                    .foregroundColor(
                                        selectedItem == nil
                                            ? .white.opacity(0.3)
                                            : Color(red: 1.0, green: 0.8, blue: 0.0)
                                    )
                                }
                                .disabled(selectedItem == nil)
                                .frame(maxWidth: .infinity)
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 20)
                        }
                        .background(
                            Rectangle()
                                .fill(Color(red: 0.12, green: 0.13, blue: 0.16))
                                .overlay(
                                    Rectangle()
                                        .stroke(
                                            LinearGradient(
                                                colors: [
                                                    Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.3),
                                                    Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.05)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1
                                        )
                                )
                        )
                        .padding(.horizontal)
                        .padding(.top, 10)
                        
                        // 配方树结果区域
                        if showTree, let root = vm.rootNode {
                            VStack(spacing: 16) {
                                
                                // 统计信息栏
                                VStack(spacing: 0) {
                                    // 标题
                                    HStack {
                                        Rectangle()
                                            .fill(Color(red: 1.0, green: 0.8, blue: 0.0))
                                            .frame(width: 3, height: 16)
                                        
                                        Text("ANALYSIS RESULT")
                                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                                            .foregroundColor(.white.opacity(0.8))
                                        
                                        Spacer()
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(Color(red: 0.08, green: 0.09, blue: 0.12))
                                    
                                    // 统计数据
                                    HStack(spacing: 0) {
                                        EndFieldStatCard(
                                            icon: "clock.fill",
                                            title: "TIME",
                                            value: "\(root.totalTime)",
                                            unit: "SEC",
                                            color: Color(red: 0.9, green: 0.5, blue: 0.2)
                                        )
                                        
                                        Divider()
                                            .overlay(Color.white.opacity(0.1))
                                        
                                        EndFieldStatCard(
                                            icon: "gearshape.2.fill",
                                            title: "BATCH",
                                            value: "\(root.batches)",
                                            unit: "CNT",
                                            color: Color(red: 0.6, green: 0.4, blue: 0.9)
                                        )
                                        
                                        Divider()
                                            .overlay(Color.white.opacity(0.1))
                                        
                                        EndFieldStatCard(
                                            icon: "arrow.triangle.branch",
                                            title: "STEPS",
                                            value: "\(countNodes(root))",
                                            unit: "CNT",
                                            color: Color(red: 0.4, green: 0.8, blue: 0.2)
                                        )
                                    }
                                    .frame(height: 80)
                                    .background(Color(red: 0.12, green: 0.13, blue: 0.16))
                                }
                                .background(
                                    Rectangle()
                                        .stroke(Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.2), lineWidth: 1)
                                )
                                .padding(.horizontal)
                                .padding(.top, 16)
                                
                                // 缩略图预览
                                VStack(spacing: 0) {
                                    // 标题栏
                                    HStack {
                                        Rectangle()
                                            .fill(Color(red: 1.0, green: 0.8, blue: 0.0))
                                            .frame(width: 3, height: 16)
                                        
                                        Text("PRODUCTION TREE")
                                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                                            .foregroundColor(.white.opacity(0.8))
                                        
                                        Spacer()
                                        
                                        Text("PREVIEW")
                                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                                            .foregroundColor(.white.opacity(0.4))
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(Color(red: 0.08, green: 0.09, blue: 0.12))
                                    
                                    // 缩略图
                                    ZStack {
                                        ThumbnailPreview(root: root)
                                            .frame(height: 300)
                                            .background(Color(red: 0.12, green: 0.13, blue: 0.16))
                                        
                                        // 展开按钮
                                        VStack {
                                            Spacer()
                                            
                                            Button {
                                                showDetailView = true
                                            } label: {
                                                HStack(spacing: 6) {
                                                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                                                    Text("VIEW FULL TREE")
                                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                                }
                                                .padding(.horizontal, 20)
                                                .padding(.vertical, 12)
                                                .background(
                                                    ZStack {
                                                        Rectangle()
                                                            .fill(Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.2))
                                                        Rectangle()
                                                            .stroke(Color(red: 1.0, green: 0.8, blue: 0.0), lineWidth: 2)
                                                    }
                                                )
                                                .foregroundColor(Color(red: 1.0, green: 0.8, blue: 0.0))
                                            }
                                            .padding(.bottom, 20)
                                        }
                                    }
                                    .onTapGesture {
                                        showDetailView = true
                                    }
                                }
                                .background(
                                    Rectangle()
                                        .stroke(Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.2), lineWidth: 1)
                                )
                                .padding(.horizontal)
                            }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            
                        } else if showTree {
                            VStack(spacing: 16) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 60))
                                    .foregroundColor(.red.opacity(0.5))
                                
                                Text("ERROR: RECIPE NOT FOUND")
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    .foregroundColor(.red.opacity(0.8))
                                
                                Text("未找到配方数据")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.6))
                            }
                            .frame(maxHeight: .infinity)
                            .padding(.top, 60)
                        }
                        
                        Spacer(minLength: 40)
                    }
                }
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .foregroundColor(Color(red: 1.0, green: 0.8, blue: 0.0))
                        
                        Text("RECIPE ANALYSIS")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color(red: 0.08, green: 0.09, blue: 0.12), for: .navigationBar)
            .sheet(isPresented: $showDetailView) {
                if let root = vm.rootNode {
                    RecipeDetailView(root: root)
                }
            }
            .onAppear {
                if selectedItem == nil {
                    selectedItem = vm.recipes.keys.sorted().first
                }
            }
        }
    }
    
    private func countNodes(_ node: RecipeNode) -> Int {
        return 1 + node.children.reduce(0) { $0 + countNodes($1) }
    }
}

// 终末地风格统计卡片
struct EndFieldStatCard: View {
    let icon: String
    let title: String
    let value: String
    let unit: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
            
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .foregroundColor(color)
            
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
            
            Text(unit)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
    }
}

// 缩略图预览组件
struct ThumbnailPreview: View {
    let root: RecipeNode
    
    private let nodeWidth: CGFloat = 80
    private let nodeHeight: CGFloat = 50
    private let xSpacing: CGFloat = 90
    private let ySpacing: CGFloat = 70
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 连线层
                Canvas { context, size in
                    drawConnections(node: root, context: &context)
                }
                
                // 节点层
                ThumbnailNodeView(
                    node: root,
                    nodeWidth: nodeWidth,
                    nodeHeight: nodeHeight,
                    xSpacing: xSpacing,
                    ySpacing: ySpacing
                )
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .scaleEffect(calculateScale(in: geometry.size))
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .clipped()
    }
    
    private func calculateScale(in size: CGSize) -> CGFloat {
        let maxX = findMaxX(node: root)
        let maxLevel = findMaxLevel(node: root)
        
        let treeWidth = (maxX + 1) * xSpacing
        let treeHeight = CGFloat(maxLevel + 1) * ySpacing
        
        let scaleX = (size.width - 40) / treeWidth
        let scaleY = (size.height - 40) / treeHeight
        
        return min(scaleX, scaleY, 1.0)
    }
    
    private func findMaxX(node: RecipeNode) -> CGFloat {
        var maxX = node.positionX
        for child in node.children {
            maxX = max(maxX, findMaxX(node: child))
        }
        return maxX
    }
    
    private func findMaxLevel(node: RecipeNode) -> Int {
        var maxLevel = node.level
        for child in node.children {
            maxLevel = max(maxLevel, findMaxLevel(node: child))
        }
        return maxLevel
    }
    
    private func drawConnections(
        node: RecipeNode,
        context: inout GraphicsContext
    ) {
        for child in node.children {
            let start = CGPoint(
                x: child.positionX * xSpacing + nodeWidth / 2,
                y: CGFloat(child.level) * ySpacing + nodeHeight / 2
            )
            
            let end = CGPoint(
                x: node.positionX * xSpacing + nodeWidth / 2,
                y: CGFloat(node.level) * ySpacing - nodeHeight / 2
            )
            
            var path = Path()
            path.move(to: start)
            
            let controlPoint1 = CGPoint(
                x: start.x,
                y: start.y + (end.y - start.y) * 0.5
            )
            let controlPoint2 = CGPoint(
                x: end.x,
                y: start.y + (end.y - start.y) * 0.5
            )
            
            path.addCurve(to: end, control1: controlPoint1, control2: controlPoint2)
            
            context.stroke(path, with: .color(Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.3)), lineWidth: 1.5)
            
            drawConnections(node: child, context: &context)
        }
    }
}

// 缩略图节点视图
struct ThumbnailNodeView: View {
    let node: RecipeNode
    let nodeWidth: CGFloat
    let nodeHeight: CGFloat
    let xSpacing: CGFloat
    let ySpacing: CGFloat
    
    var body: some View {
        ZStack {
            nodeThumbnail(node)
                .position(
                    x: node.positionX * xSpacing + nodeWidth / 2,
                    y: CGFloat(node.level) * ySpacing
                )
            
            ForEach(node.children) { child in
                ThumbnailNodeView(
                    node: child,
                    nodeWidth: nodeWidth,
                    nodeHeight: nodeHeight,
                    xSpacing: xSpacing,
                    ySpacing: ySpacing
                )
            }
        }
    }
    
    private func nodeThumbnail(_ node: RecipeNode) -> some View {
        VStack(spacing: 2) {
            Text(node.name)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
            
            Text("x\(node.amount)")
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(width: nodeWidth, height: nodeHeight)
        .background(
            ZStack {
                Rectangle()
                    .fill(
                        node.recipe == nil
                            ? Color(red: 0.9, green: 0.5, blue: 0.2).opacity(0.2)
                            : Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.2)
                    )
                Rectangle()
                    .stroke(
                        node.recipe == nil
                            ? Color(red: 0.9, green: 0.5, blue: 0.2).opacity(0.5)
                            : Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.5),
                        lineWidth: 1
                    )
            }
        )
    }
}
