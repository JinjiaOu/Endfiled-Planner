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
    @State private var showsOutline = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    
    private var initialXOffset: CGFloat {
        -(root.positionX * xSpacing)
    }

    private var initialYOffset: CGFloat {
        -(CGFloat(findMaxLevel(node: root)) * ySpacing) / 2
    }
    
    private let nodeWidth: CGFloat = 160
    private let nodeHeight: CGFloat = 100
    private let xSpacing: CGFloat = 200
    private let ySpacing: CGFloat = 160
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppTopographicBackground()
                if showsOutline {
                    ScrollView {
                        RecipeDependencyOutline(node: root)
                            .padding(AppSpacing.md)
                            .frame(maxWidth: 840, alignment: .leading)
                            .frame(maxWidth: .infinity)
                    }
                } else {
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
                                    .onEnded { _ in
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
                                    .onEnded { _ in
                                        lastOffset = offset
                                    }
                            )
                        )
                    }
                    .clipped()
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(root.name).font(AppTypography.rowTitle).foregroundStyle(AppColors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Picker("查看方式", selection: $showsOutline) {
                        Text("图形").tag(false)
                        Text("依赖清单").tag(true)
                    }
                    .pickerStyle(.segmented)
                }
                .padding(AppSpacing.sm)
                .background(AppColors.surface)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !showsOutline { zoomControls }
            }
            .navigationTitle("完整配方树")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { saveAsImage() } label: { Label("保存配方树图片", systemImage: "square.and.arrow.down") }
                        Button { shareImage() } label: { Label("分享配方树图片", systemImage: "square.and.arrow.up") }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("保存与分享配方树")
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(AppColors.background, for: .navigationBar)
            .tint(AppColors.accent)
            .onAppear { if dynamicTypeSize.isAccessibilitySize { showsOutline = true } }
            .onChange(of: dynamicTypeSize) { _, size in if size.isAccessibilitySize { showsOutline = true } }
            .alert("保存图片", isPresented: $showingSaveAlert) {
                Button("确定", role: .cancel) { }
            } message: { Text(saveMessage) }
        }
    }

    private var zoomControls: some View {
        HStack(spacing: AppSpacing.xs) {
            AppIconButton(title: "缩小配方树", systemImage: "minus.magnifyingglass") {
                withAnimation(AppMotion.feedback(reduceMotion: reduceMotion)) {
                    scale = max(scale / 1.2, 0.3)
                    lastScale = scale
                }
            }
            Text("\(Int(scale * 100))%")
                .font(AppTypography.numeric).foregroundStyle(AppColors.primaryText)
                .frame(minWidth: 60)
                .accessibilityLabel("缩放比例 \(Int(scale * 100))%")
            AppIconButton(title: "放大配方树", systemImage: "plus.magnifyingglass") {
                withAnimation(AppMotion.feedback(reduceMotion: reduceMotion)) {
                    scale = min(scale * 1.2, 3.0)
                    lastScale = scale
                }
            }
            Spacer(minLength: 0)
            AppIconButton(title: "重置视图", systemImage: "arrow.counterclockwise") {
                withAnimation(AppMotion.feedback(reduceMotion: reduceMotion)) {
                    scale = 0.5
                    lastScale = 0.5
                    offset = .zero
                    lastOffset = .zero
                }
            }
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xxs)
        .background(AppColors.surface)
        .overlay(alignment: .top) { Divider().overlay(AppColors.border) }
    }

    // MARK: - 保存功能
    
    private func saveAsImage() {
        let renderer = ImageRenderer(content: currentView().environment(\.colorScheme, colorScheme))
        renderer.scale = 3.0
        if let image = renderer.uiImage {
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            saveMessage = "图片已保存到相册"
        } else {
            saveMessage = "保存失败"
        }
        showingSaveAlert = true
    }
    
    private func shareImage() {
        let renderer = ImageRenderer(content: currentView().environment(\.colorScheme, colorScheme))
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
    
    @ViewBuilder
    private func currentView() -> some View {
        GeometryReader { geometry in
            ZStack {
                AppColors.background
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
                    context.stroke(path, with: .color(AppColors.accent.opacity(0.1)), lineWidth: 0.5)
                }
                ZStack {
                    Canvas { context, size in drawConnections(node: root, context: &context) }
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
            // 原料子节点位于下方：从其上边缘连向成品节点下边缘。
            let start = CGPoint(x: child.positionX * xSpacing + nodeWidth / 2, y: CGFloat(child.level) * ySpacing - nodeHeight / 2)
            let end   = CGPoint(x: node.positionX  * xSpacing + nodeWidth / 2, y: CGFloat(node.level)  * ySpacing + nodeHeight / 2)
            var path = Path()
            path.move(to: start)
            path.addCurve(to: end,
                          control1: CGPoint(x: start.x, y: start.y + (end.y - start.y) * 0.5),
                          control2: CGPoint(x: end.x,   y: start.y + (end.y - start.y) * 0.5))
            context.stroke(path, with: .color(AppColors.accent.opacity(0.3)), lineWidth: 2.5)
            drawArrow(at: end, context: &context)
            drawConnections(node: child, context: &context)
        }
    }
    
    private func drawArrow(at point: CGPoint, context: inout GraphicsContext) {
        var path = Path()
        path.move(to: CGPoint(x: point.x - 4, y: point.y + 8))
        path.addLine(to: point)
        path.addLine(to: CGPoint(x: point.x + 4, y: point.y + 8))
        path.closeSubpath()
        context.fill(path, with: .color(AppColors.accent.opacity(0.5)))
    }
}

// MARK: - DetailNodeView

struct DetailNodeView: View {
    let node: RecipeNode
    let nodeWidth: CGFloat
    let nodeHeight: CGFloat
    let xSpacing: CGFloat
    let ySpacing: CGFloat
    
    var body: some View {
        ZStack {
            nodeCard(node)
                .position(x: node.positionX * xSpacing + nodeWidth / 2,
                          y: CGFloat(node.level) * ySpacing)
            ForEach(node.children) { child in
                DetailNodeView(node: child,
                               nodeWidth: nodeWidth,
                               nodeHeight: nodeHeight,
                               xSpacing: xSpacing,
                               ySpacing: ySpacing)
            }
        }
    }
    
    private func nodeCard(_ node: RecipeNode) -> some View {
        RecipeDiagramCard(node: node)
            .frame(width: nodeWidth, height: nodeHeight)
    }
}
