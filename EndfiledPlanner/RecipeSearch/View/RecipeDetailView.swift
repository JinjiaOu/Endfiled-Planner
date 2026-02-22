//
//  RecipeDetailView.swift
//  EndfiledPlanner
//
//  Created by Jinjia Ou on 2/14/26.
//

import SwiftUI

struct RecipeDetailView: View {
    
    let root: RecipeNode
    
    @Environment(\.dismiss) var dismiss
    @State private var scale: CGFloat = 0.5
    @State private var lastScale: CGFloat = 0.5
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var showingSaveAlert = false
    @State private var saveMessage = ""
    
    // 根据根节点位置调整的初始偏移
    private let initialXOffset: CGFloat = -500 // 让根节点水平居中
    private let initialYOffset: CGFloat = -500
    
    private let nodeWidth: CGFloat = 160
    private let nodeHeight: CGFloat = 100
    private let xSpacing: CGFloat = 200
    private let ySpacing: CGFloat = 160
    
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
                        with: .color(Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.1)),
                        lineWidth: 0.5
                    )
                }
                .ignoresSafeArea()
                
                // 配方树
                GeometryReader { geometry in
                    ZStack {
                        Canvas { context, size in
                            drawConnections(node: root, context: &context)
                        }
                        
                        DetailNodeView(
                            node: root,
                            nodeWidth: nodeWidth,
                            nodeHeight: nodeHeight,
                            xSpacing: xSpacing,
                            ySpacing: ySpacing
                        )
                    }
                    .frame(width: calculateWidth(), height: calculateHeight())
                    .scaleEffect(scale)
                    .offset(x: geometry.size.width / 2 + offset.width + initialXOffset,
                           y: geometry.size.height / 2 + offset.height + initialYOffset)
                    .gesture(
                        SimultaneousGesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    scale = lastScale * value
                                }
                                .onEnded { value in
                                    lastScale = scale
                                    scale = min(max(scale, 0.3), 3.0)
                                    lastScale = scale
                                },
                            DragGesture()
                                .onChanged { value in
                                    offset = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )
                                }
                                .onEnded { value in
                                    lastOffset = offset
                                }
                        )
                    )
                }
                .clipped()
                
                // 控制按钮
                VStack {
                    HStack {
                        Spacer()
                        
                        VStack(spacing: 12) {
                            Button {
                                withAnimation(.spring(response: 0.3)) {
                                    scale = 0.5
                                    lastScale = 0.5
                                    offset = .zero
                                    lastOffset = .zero
                                }
                            } label: {
                                ZStack {
                                    Rectangle()
                                        .fill(Color(red: 0.12, green: 0.13, blue: 0.16))
                                        .frame(width: 44, height: 44)
                                    Rectangle()
                                        .stroke(Color(red: 1.0, green: 0.8, blue: 0.0), lineWidth: 2)
                                        .frame(width: 44, height: 44)
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.system(size: 18))
                                        .foregroundColor(Color(red: 1.0, green: 0.8, blue: 0.0))
                                }
                                .shadow(color: Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.3), radius: 4)
                            }
                            
                            Button {
                                withAnimation(.spring(response: 0.3)) {
                                    scale = min(scale * 1.2, 3.0)
                                    lastScale = scale
                                }
                            } label: {
                                ZStack {
                                    Rectangle()
                                        .fill(Color(red: 0.12, green: 0.13, blue: 0.16))
                                        .frame(width: 44, height: 44)
                                    Rectangle()
                                        .stroke(Color(red: 0.4, green: 0.8, blue: 0.2), lineWidth: 2)
                                        .frame(width: 44, height: 44)
                                    Image(systemName: "plus.magnifyingglass")
                                        .font(.system(size: 18))
                                        .foregroundColor(Color(red: 0.4, green: 0.8, blue: 0.2))
                                }
                                .shadow(color: Color(red: 0.4, green: 0.8, blue: 0.2).opacity(0.3), radius: 4)
                            }
                            
                            Button {
                                withAnimation(.spring(response: 0.3)) {
                                    scale = max(scale / 1.2, 0.3)
                                    lastScale = scale
                                }
                            } label: {
                                ZStack {
                                    Rectangle()
                                        .fill(Color(red: 0.12, green: 0.13, blue: 0.16))
                                        .frame(width: 44, height: 44)
                                    Rectangle()
                                        .stroke(Color(red: 0.9, green: 0.5, blue: 0.2), lineWidth: 2)
                                        .frame(width: 44, height: 44)
                                    Image(systemName: "minus.magnifyingglass")
                                        .font(.system(size: 18))
                                        .foregroundColor(Color(red: 0.9, green: 0.5, blue: 0.2))
                                }
                                .shadow(color: Color(red: 0.9, green: 0.5, blue: 0.2).opacity(0.3), radius: 4)
                            }
                        }
                        .padding(.trailing, 20)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 8) {
                        Text("ZOOM")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                        Text("\(Int(scale * 100))%")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(red: 1.0, green: 0.8, blue: 0.0))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        ZStack {
                            Rectangle().fill(Color(red: 0.12, green: 0.13, blue: 0.16))
                            Rectangle().stroke(Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.3), lineWidth: 1)
                        }
                    )
                    .padding(.bottom, 20)
                }
                .allowsHitTesting(true)
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.branch")
                            .foregroundColor(Color(red: 1.0, green: 0.8, blue: 0.0))
                        Text("FULL TREE VIEW")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    }
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("返回")
                        }
                        .foregroundColor(Color(red: 1.0, green: 0.8, blue: 0.0))
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            saveAsImage()
                        } label: {
                            Label("保存为图片", systemImage: "square.and.arrow.down")
                        }
                        
                        Button {
                            shareImage()
                        } label: {
                            Label("分享", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(Color(red: 1.0, green: 0.8, blue: 0.0))
                    }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color(red: 0.08, green: 0.09, blue: 0.12), for: .navigationBar)
            .alert("保存图片", isPresented: $showingSaveAlert) {
                Button("确定", role: .cancel) { }
            } message: {
                Text(saveMessage)
            }
        }
    }
    
    // MARK: - 保存功能
    private func saveAsImage() {
        // 使用当前视图的完整渲染，包括缩放和偏移
        let renderer = ImageRenderer(content: currentView())
        renderer.scale = 3.0
        
        if let image = renderer.uiImage {
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            saveMessage = "图片已保存到相册"
            showingSaveAlert = true
        } else {
            saveMessage = "保存失败"
            showingSaveAlert = true
        }
    }
    
    private func shareImage() {
        let renderer = ImageRenderer(content: currentView())
        renderer.scale = 3.0
        
        guard let image = renderer.uiImage else { return }
        
        let activityVC = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = scene.windows.first,
           let rootVC = window.rootViewController {
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = window
                popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
            }
            rootVC.present(activityVC, animated: true)
        }
    }
    
    // 渲染当前视图状态（包括缩放和偏移）
    @ViewBuilder
    private func currentView() -> some View {
        GeometryReader { geometry in
            ZStack {
                // 深色背景
                Color(red: 0.08, green: 0.09, blue: 0.12)
                
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
                    context.stroke(path, with: .color(Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.1)), lineWidth: 0.5)
                }
                
                // 配方树 - 应用当前的缩放和偏移
                ZStack {
                    Canvas { context, size in
                        drawConnections(node: root, context: &context)
                    }
                    DetailNodeView(node: root, nodeWidth: nodeWidth, nodeHeight: nodeHeight, xSpacing: xSpacing, ySpacing: ySpacing)
                }
                .frame(width: calculateWidth(), height: calculateHeight())
                .scaleEffect(scale)
                .offset(x: geometry.size.width / 2 + offset.width + initialXOffset,
                       y: geometry.size.height / 2 + offset.height + initialYOffset)
            }
        }
        .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
    }
    
    private func calculateWidth() -> CGFloat {
        max((findMaxX(node: root) + 1) * xSpacing + 200, 1000)
    }
    
    private func calculateHeight() -> CGFloat {
        max(CGFloat(findMaxLevel(node: root) + 1) * ySpacing + 200, 800)
    }
    
    private func findMaxX(node: RecipeNode) -> CGFloat {
        node.children.reduce(node.positionX) { max($0, findMaxX(node: $1)) }
    }
    
    private func findMaxLevel(node: RecipeNode) -> Int {
        node.children.reduce(node.level) { max($0, findMaxLevel(node: $1)) }
    }
    
    private func drawConnections(node: RecipeNode, context: inout GraphicsContext) {
        for child in node.children {
            let start = CGPoint(x: child.positionX * xSpacing + nodeWidth / 2, y: CGFloat(child.level) * ySpacing + nodeHeight / 2)
            let end = CGPoint(x: node.positionX * xSpacing + nodeWidth / 2, y: CGFloat(node.level) * ySpacing - nodeHeight / 2)
            var path = Path()
            path.move(to: start)
            let cp1 = CGPoint(x: start.x, y: start.y + (end.y - start.y) * 0.5)
            let cp2 = CGPoint(x: end.x, y: start.y + (end.y - start.y) * 0.5)
            path.addCurve(to: end, control1: cp1, control2: cp2)
            context.stroke(path, with: .color(Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.3)), lineWidth: 2.5)
            drawArrow(at: end, context: &context)
            drawConnections(node: child, context: &context)
        }
    }
    
    private func drawArrow(at point: CGPoint, context: inout GraphicsContext) {
        var path = Path()
        path.move(to: CGPoint(x: point.x - 4, y: point.y - 8))
        path.addLine(to: point)
        path.addLine(to: CGPoint(x: point.x + 4, y: point.y - 8))
        context.fill(path, with: .color(Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.5)))
    }
}

struct DetailNodeView: View {
    let node: RecipeNode
    let nodeWidth: CGFloat
    let nodeHeight: CGFloat
    let xSpacing: CGFloat
    let ySpacing: CGFloat
    
    var body: some View {
        ZStack {
            nodeCard(node).position(x: node.positionX * xSpacing + nodeWidth / 2, y: CGFloat(node.level) * ySpacing)
            ForEach(node.children) { child in
                DetailNodeView(node: child, nodeWidth: nodeWidth, nodeHeight: nodeHeight, xSpacing: xSpacing, ySpacing: ySpacing)
            }
        }
    }
    
    private func nodeCard(_ node: RecipeNode) -> some View {
        VStack(spacing: 8) {
            Text(node.name).font(.system(size: 16, weight: .semibold)).multilineTextAlignment(.center).lineLimit(2).foregroundColor(.white)
            HStack(spacing: 4) {
                Image(systemName: "cube.box.fill").font(.caption2)
                Text("x\(node.amount)").font(.system(size: 15, weight: .medium, design: .monospaced))
            }
            .foregroundColor(.white.opacity(0.7))
            if let recipe = node.recipe {
                VStack(spacing: 2) {
                    Text(recipe.machine).font(.system(size: 11, weight: .medium)).foregroundColor(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(machineColor(recipe.machine)))
                    if recipe.time > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "clock.fill").font(.system(size: 8))
                            Text("\(recipe.time)s").font(.system(size: 9, design: .monospaced))
                        }
                        .foregroundColor(.white.opacity(0.5))
                    }
                }
            }
        }
        .frame(width: nodeWidth, height: nodeHeight)
        .background(
            ZStack {
                Rectangle().fill(node.recipe == nil ? Color(red: 0.9, green: 0.5, blue: 0.2).opacity(0.15) : Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.15))
                Rectangle().stroke(node.recipe == nil ? Color(red: 0.9, green: 0.5, blue: 0.2).opacity(0.5) : Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.5), lineWidth: 2)
            }
        )
        .shadow(color: Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.1), radius: 5, x: 0, y: 3)
    }
    
    private func machineColor(_ machine: String) -> Color {
        switch machine {
        case let m where m.contains("矿机"): return Color(red: 0.6, green: 0.4, blue: 0.2)
        case let m where m.contains("精炼"): return Color(red: 0.9, green: 0.3, blue: 0.2)
        case let m where m.contains("装配"): return Color(red: 0.6, green: 0.4, blue: 0.9)
        case let m where m.contains("粉碎"): return Color(red: 0.5, green: 0.5, blue: 0.5)
        case let m where m.contains("封装"): return Color(red: 0.4, green: 0.8, blue: 0.2)
        default: return Color(red: 1.0, green: 0.8, blue: 0.0)
        }
    }
}
