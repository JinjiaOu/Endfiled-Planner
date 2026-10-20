// Created by Jinjia Ou on 10/20/26.

import SwiftUI

/// 仅绘制设备外壳；不生成端口，也不参与碰撞、连线和网格坐标计算。
struct FactoryBuildingShell: View {
    var circularInset: Bool

    var body: some View {
        Canvas { context, size in
            let unit = min(size.width, size.height)
            let inset = max(2, unit * 0.035)
            let bounds = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
            let shell = Path(bounds)
            context.fill(shell, with: .color(FactoryCanvasPalette.building))
            context.stroke(shell, with: .color(FactoryCanvasPalette.ink.opacity(0.8)), lineWidth: max(1, unit * 0.012))

            let inner = bounds.insetBy(dx: max(3, unit * 0.055), dy: max(3, unit * 0.055))
            if inner.width > 0, inner.height > 0 {
                let innerPath = Path(inner)
                context.stroke(innerPath, with: .color(FactoryCanvasPalette.structure.opacity(0.55)), lineWidth: 0.8)
            }
            if circularInset, inner.width > 0, inner.height > 0 {
                // 外壳及占地仍为方形；圆环只作为供电设施的内部符号。
                let diameter = min(inner.width, inner.height) * 0.82
                let ring = CGRect(x: bounds.midX - diameter / 2, y: bounds.midY - diameter / 2,
                                  width: diameter, height: diameter)
                context.stroke(Path(ellipseIn: ring), with: .color(FactoryCanvasPalette.structure), lineWidth: 0.8)
            }
            if unit >= 32 {
                // 设备角部固定件，实际连接槽由 portsLayer 依照真实端口单独绘制。
                let screw = max(1.5, min(3, unit * 0.025))
                for x in [bounds.minX + inset, bounds.maxX - inset] {
                    for y in [bounds.minY + inset, bounds.maxY - inset] {
                        let mark = CGRect(x: x - screw / 2, y: y - screw / 2, width: screw, height: screw)
                        context.fill(Path(mark), with: .color(FactoryCanvasPalette.structure))
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

}
