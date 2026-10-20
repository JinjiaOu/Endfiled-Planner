// Created by Jinjia Ou on 10/20/26.

import SwiftUI

/// 装饰底纹不参与布局、点击或业务状态；等高线路径只生成一次。
struct AppTopographicBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var isVisible = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion || !isVisible || scenePhase != .active || ProcessInfo.processInfo.isLowPowerModeEnabled)) { timeline in
            let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate / 45
            Canvas { context, size in
                let scale = max(size.width / 1200, size.height / 900) * 1.04
                context.translateBy(x: size.width / 2 + sin(time) * 12,
                                    y: size.height / 2 + cos(time * 0.7) * 12)
                context.scaleBy(x: scale, y: scale)
                context.translateBy(x: -600, y: -450)
                for (index, path) in TopographicContours.paths.enumerated() {
                    let major = index.isMultiple(of: 4)
                    context.stroke(path, with: .color(AppColors.secondaryText.opacity(contrast == .increased ? 0.16 : (major ? 0.12 : 0.065))),
                                   lineWidth: (major ? 0.6 : 0.35) / scale)
                }
            }
            .background(AppColors.background)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
    }
}

private enum TopographicContours {
    /// 对固定多峰高度场提取等高线，不在动画帧里重新采样。
    static let paths: [Path] = {
        let columns = 160, rows = 120
        func height(_ x: Double, _ y: Double) -> Double {
            let a = exp(-((x - 0.25) * (x - 0.25) * 9 + (y - 0.35) * (y - 0.35) * 12))
            let b = exp(-((x - 0.83) * (x - 0.83) * 16 + (y - 0.77) * (y - 0.77) * 10))
            return a + b * 0.85 + sin(x * 9 + y * 3) * 0.12 + cos(y * 8 - x * 2) * 0.1
        }
        let samples = (0...rows).map { row in
            (0...columns).map { col in height(Double(col) / Double(columns), Double(row) / Double(rows)) }
        }
        return (0..<38).map { levelIndex in
            let level = Double(levelIndex) * 0.0375 - 0.15
            var path = Path()
            for row in 0..<rows {
                for col in 0..<columns {
                    let values = [samples[row][col], samples[row][col + 1], samples[row + 1][col + 1], samples[row + 1][col]]
                    let points = [CGPoint(x: CGFloat(col) * 7.5, y: CGFloat(row) * 7.5), CGPoint(x: CGFloat(col + 1) * 7.5, y: CGFloat(row) * 7.5),
                                  CGPoint(x: CGFloat(col + 1) * 7.5, y: CGFloat(row + 1) * 7.5), CGPoint(x: CGFloat(col) * 7.5, y: CGFloat(row + 1) * 7.5)]
                    var crossings: [CGPoint] = []
                    for edge in 0..<4 {
                        let next = (edge + 1) % 4
                        guard (values[edge] < level) != (values[next] < level) else { continue }
                        let fraction = CGFloat((level - values[edge]) / (values[next] - values[edge]))
                        crossings.append(CGPoint(x: points[edge].x + (points[next].x - points[edge].x) * fraction,
                                                 y: points[edge].y + (points[next].y - points[edge].y) * fraction))
                    }
                    // 固定边序处理鞍点，保证整个背景在动画期间拓扑稳定。
                    if crossings.count >= 2 {
                        for index in stride(from: 0, to: crossings.count - 1, by: 2) {
                            path.move(to: crossings[index])
                            path.addLine(to: crossings[index + 1])
                        }
                    }
                }
            }
            return path
        }
    }()
}
