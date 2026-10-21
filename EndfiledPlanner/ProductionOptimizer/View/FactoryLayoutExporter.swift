// Created by Jinjia Ou on 10/20/26.

import SwiftUI
import UIKit

/// 把当前画布渲染成一张图片：固定格子尺寸渲染整张网格，再裁到有内容的区域（四周留 2 格）。
/// 四号谷地外围的仓库存取线示意在内容贴近上/左边时一起带上
@MainActor
enum FactoryLayoutExporter {
    /// 导出用的格子尺寸：够看清产物图标（FactoryGridView.productIconMinCellSize），整图又不至于太大
    static let cellSize: CGFloat = 24
    static let scale: CGFloat = 2
    private static let margin = 2

    static func image(vm: FactoryViewModel, colorScheme: ColorScheme) -> UIImage? {
        let rules = vm.layout.mapType.rules
        var cells: [GridPoint] = vm.layout.beltNetwork.allSegments.map(\.cell)
        for placed in vm.layout.buildings {
            guard let def = BuildingDefinition.find(placed.definitionID) else { continue }
            cells += placed.occupiedCells(definition: def)
        }
        guard let minCol = cells.map(\.col).min(), let maxCol = cells.map(\.col).max(),
              let minRow = cells.map(\.row).min(), let maxRow = cells.map(\.row).max() else { return nil }

        // 外围存取线示意占的格数（跟 FactoryLayoutView.warehouseMargin 一致）
        var topCells = 0, leadingCells = 0
        if case .perimeter(let edges) = rules.warehouseLine {
            if edges.contains(.up) { topCells = FactoryGridView.warehouseLineDepth }
            if edges.contains(.left) { leadingCells = FactoryGridView.warehouseLineDepth }
        }

        let content = FactoryGridView(vm: vm, cellSize: cellSize,
                                      draggingDef: .constant(nil),
                                      dragLocationInGrid: .constant(nil),
                                      autoScrollFinger: .constant(nil))
            .padding(.top, CGFloat(topCells) * cellSize)
            .padding(.leading, CGFloat(leadingCells) * cellSize)
            .background(FactoryCanvasPalette.background)
            .environment(\.colorScheme, colorScheme)

        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        guard let full = renderer.cgImage else { return nil }

        // 裁剪范围（格子坐标，含外围示意的偏移）；内容贴近上/左边时把存取线示意整条带上
        let col0 = minCol - margin <= 0 ? -leadingCells : minCol - margin
        let row0 = minRow - margin <= 0 ? -topCells : minRow - margin
        let col1 = min(rules.gridCols, maxCol + 1 + margin)
        let row1 = min(rules.gridRows, maxRow + 1 + margin)
        let unit = cellSize * scale
        let crop = CGRect(x: CGFloat(col0 + leadingCells) * unit, y: CGFloat(row0 + topCells) * unit,
                          width: CGFloat(col1 - col0) * unit, height: CGFloat(row1 - row0) * unit)
            .intersection(CGRect(x: 0, y: 0, width: full.width, height: full.height))
        guard let cropped = full.cropping(to: crop) else { return UIImage(cgImage: full) }
        return UIImage(cgImage: cropped, scale: scale, orientation: .up)
    }

    /// 弹系统分享面板（可存相册、发微信等）
    static func share(_ image: UIImage) {
        let activityVC = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
                ?? UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first,
              var top = window.rootViewController else { return }
        while let presented = top.presentedViewController { top = presented }
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = window
            popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        top.present(activityVC, animated: true)
    }
}
