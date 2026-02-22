//
//  RecipeFlowView.swift
//  EndfiledPlanner
//
//  Created by Jinjia Ou on 2/14/26.
//

import SwiftUI

struct RecipeFlowView: View {
    
    let root: RecipeNode
    
    private let nodeWidth: CGFloat = 160
    private let nodeHeight: CGFloat = 100
    private let xSpacing: CGFloat = 200
    private let ySpacing: CGFloat = 160
    
    @State private var scale: CGFloat = 1.0
    
    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            ZStack {
                // 背景网格（可选）
                GridPattern()
                    .stroke(Color.gray.opacity(0.1), lineWidth: 0.5)
                
                // 连线层
                Canvas { context, size in
                    drawConnections(node: root, context: &context)
                }
                
                // 节点层
                NodeViewRecursive(
                    node: root,
                    nodeWidth: nodeWidth,
                    nodeHeight: nodeHeight,
                    xSpacing: xSpacing,
                    ySpacing: ySpacing
                )
            }
            .frame(width: max(2000, calculateWidth()),
                   height: max(1500, calculateHeight()))
            .scaleEffect(scale)
        }
        .gesture(
            MagnificationGesture()
                .onChanged { value in
                    scale = value
                }
        )
    }
    
    private func calculateWidth() -> CGFloat {
        let maxX = findMaxX(node: root)
        return (maxX + 1) * xSpacing + 200
    }
    
    private func calculateHeight() -> CGFloat {
        let maxLevel = findMaxLevel(node: root)
        return CGFloat(maxLevel + 1) * ySpacing + 200
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
            
            // 使用贝塞尔曲线使连线更优雅
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
            
            path.addCurve(to: end,
                         control1: controlPoint1,
                         control2: controlPoint2)
            
            // 渐变色连线
            context.stroke(path,
                           with: .color(.blue.opacity(0.3)),
                           lineWidth: 2.5)
            
            // 添加箭头
            drawArrow(at: end, context: &context)
            
            drawConnections(node: child, context: &context)
        }
    }
    
    private func drawArrow(at point: CGPoint, context: inout GraphicsContext) {
        let arrowSize: CGFloat = 8
        var arrowPath = Path()
        arrowPath.move(to: CGPoint(x: point.x - arrowSize/2, y: point.y - arrowSize))
        arrowPath.addLine(to: point)
        arrowPath.addLine(to: CGPoint(x: point.x + arrowSize/2, y: point.y - arrowSize))
        
        context.fill(arrowPath, with: .color(.blue.opacity(0.5)))
    }
}

// 背景网格图案
struct GridPattern: Shape {
    let spacing: CGFloat = 50
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // 垂直线
        var x: CGFloat = 0
        while x <= rect.width {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: rect.height))
            x += spacing
        }
        
        // 水平线
        var y: CGFloat = 0
        while y <= rect.height {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: rect.width, y: y))
            y += spacing
        }
        
        return path
    }
}

struct NodeViewRecursive: View {
    
    let node: RecipeNode
    let nodeWidth: CGFloat
    let nodeHeight: CGFloat
    let xSpacing: CGFloat
    let ySpacing: CGFloat
    
    var body: some View {
        ZStack {
            
            nodeCard(node)
                .position(
                    x: node.positionX * xSpacing + nodeWidth / 2,
                    y: CGFloat(node.level) * ySpacing
                )
            
            ForEach(node.children) { child in
                NodeViewRecursive(
                    node: child,
                    nodeWidth: nodeWidth,
                    nodeHeight: nodeHeight,
                    xSpacing: xSpacing,
                    ySpacing: ySpacing
                )
            }
        }
    }
    
    private func nodeCard(_ node: RecipeNode) -> some View {
        VStack(spacing: 8) {
            
            // 物品名称
            Text(node.name)
                .font(.system(size: 16, weight: .semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .foregroundColor(.primary)
            
            // 数量标签
            HStack(spacing: 4) {
                Image(systemName: "cube.box.fill")
                    .font(.caption2)
                Text("\(node.amount)")
                    .font(.system(size: 15, weight: .medium))
            }
            .foregroundColor(.secondary)
            
            // 机器信息
            if let recipe = node.recipe {
                VStack(spacing: 2) {
                    Text(recipe.machine)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(machineColor(recipe.machine))
                        )
                    
                    // 时间信息
                    if recipe.time > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 9))
                            Text("\(recipe.time)s")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(.secondary)
                    }
                }
            }
        }
        .frame(width: nodeWidth, height: nodeHeight)
        .background(
            ZStack {
                // 渐变背景
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: node.recipe == nil
                                ? [Color.orange.opacity(0.15), Color.orange.opacity(0.25)]
                                : [Color.blue.opacity(0.15), Color.cyan.opacity(0.25)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                // 边框
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        node.recipe == nil
                            ? Color.orange.opacity(0.4)
                            : Color.blue.opacity(0.4),
                        lineWidth: 2
                    )
            }
        )
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 3)
    }
    
    private func machineColor(_ machine: String) -> Color {
        // 根据不同机器类型返回不同颜色
        switch machine {
        case let m where m.contains("矿机"):
            return Color.brown
        case let m where m.contains("精炼"):
            return Color.red
        case let m where m.contains("装配"):
            return Color.purple
        case let m where m.contains("粉碎"):
            return Color.gray
        case let m where m.contains("封装"):
            return Color.green
        default:
            return Color.blue
        }
    }
}
