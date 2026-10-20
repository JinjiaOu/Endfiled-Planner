// Created by Jinjia Ou on 10/20/26.

import SwiftUI

/// 仅绘制设备外壳；不生成端口，也不参与碰撞、连线和网格坐标计算。
/// 样式参照官方蓝图：浅色机身 + 深色粗边框，上下边缘有固定卡扣；供电设施画成带四个耳片的圆环。
struct FactoryBuildingShell: View {
    var circularInset: Bool

    var body: some View {
        Canvas { context, size in
            let unit = min(size.width, size.height)
            let inset = max(2, unit * 0.035)
            let bounds = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
            let frameWidth = max(1.2, unit * 0.03)

            if circularInset {
                // 外观为圆形，占地仍是方形格子
                let diameter = min(bounds.width, bounds.height) * 0.86
                let ring = CGRect(x: bounds.midX - diameter / 2, y: bounds.midY - diameter / 2,
                                  width: diameter, height: diameter)
                // 四个 45° 方向的耳片：先画在圆环下面
                let lug = diameter * 0.13
                for angle in [45.0, 135.0, 225.0, 315.0] {
                    let rad = angle * .pi / 180
                    let r = diameter / 2
                    let center = CGPoint(x: ring.midX + CGFloat(cos(rad)) * r, y: ring.midY + CGFloat(sin(rad)) * r)
                    var arm = Path()
                    arm.move(to: CGPoint(x: ring.midX + CGFloat(cos(rad)) * r * 0.8, y: ring.midY + CGFloat(sin(rad)) * r * 0.8))
                    arm.addLine(to: center)
                    context.stroke(arm, with: .color(FactoryCanvasPalette.ink.opacity(0.8)), lineWidth: lug * 0.45)
                    let lugRect = CGRect(x: center.x - lug / 2, y: center.y - lug / 2, width: lug, height: lug)
                    context.fill(Path(ellipseIn: lugRect), with: .color(FactoryCanvasPalette.building))
                    context.stroke(Path(ellipseIn: lugRect), with: .color(FactoryCanvasPalette.ink.opacity(0.8)), lineWidth: frameWidth * 0.6)
                }
                context.fill(Path(ellipseIn: ring), with: .color(FactoryCanvasPalette.building))
                context.stroke(Path(ellipseIn: ring), with: .color(FactoryCanvasPalette.structure), lineWidth: frameWidth)
                let inner = ring.insetBy(dx: diameter * 0.08, dy: diameter * 0.08)
                context.stroke(Path(ellipseIn: inner), with: .color(FactoryCanvasPalette.structure.opacity(0.5)), lineWidth: 0.8)
                return
            }

            let shell = Path(bounds)
            context.fill(shell, with: .color(FactoryCanvasPalette.building))
            context.stroke(shell, with: .color(FactoryCanvasPalette.ink.opacity(0.85)), lineWidth: frameWidth)

            if unit >= 32 {
                // 上下边缘的卡扣：每条边两端各一个短横条
                let tabW = max(4, unit * 0.09)
                let tabH = max(1.5, unit * 0.025)
                for y in [bounds.minY + frameWidth, bounds.maxY - frameWidth - tabH] {
                    for x in [bounds.minX + unit * 0.06, bounds.maxX - unit * 0.06 - tabW] {
                        let tab = CGRect(x: x, y: y, width: tabW, height: tabH)
                        context.fill(Path(tab), with: .color(FactoryCanvasPalette.structure.opacity(0.7)))
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

}
