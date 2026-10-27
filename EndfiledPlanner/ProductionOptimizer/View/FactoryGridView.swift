//
//  FactoryGridView.swift
//  EndfiledPlanner
//
//  Created by Jinjia Ou on 4/3/26.
//

import SwiftUI

struct FactoryGridView: View {

    @ObservedObject var vm: FactoryViewModel
    let cellSize: CGFloat

    // 从建筑板拖入时的状态（由父视图控制）
    @Binding var draggingDef: BuildingDefinition?
    @Binding var dragLocationInGrid: CGPoint?
    /// 框选拉框/拖整组时手指的全局坐标，父视图据此在手指靠近画面边缘时自动滚动；没在拖时为 nil
    @Binding var autoScrollFinger: CGPoint?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var beltAnimPhase: CGFloat = 0
    // dragLocationInGrid 是父视图传来的"手指全局坐标"，这里换算成网格本地坐标用来画预览——
    // 单独存一份而不是写回 dragLocationInGrid，避免它被当成新的全局坐标再转一遍，越转越偏
    @State private var dropPreviewLocal: CGPoint? = nil

    // 已放置建筑拖拽重定位：只在"当前选中建筑自己的那块区域"响应拖拽手势，不碰整个网格的
    // gestureOverlay，这样滚动/点选其它地方完全不受影响，只有摸到选中建筑本体才会触发挪动
    @State private var repositionOriginalOrigin: GridPoint? = nil
    @State private var repositionCandidateOrigin: GridPoint? = nil
    /// 删除工具按住划过时上一次删的格子，避免同一格重复触发
    @State private var lastErasedCell: GridPoint? = nil
    @State private var eraseDragActive = false
    /// 框选模式：这次拖动是在拉框还是在拖整组（按下的那格是选中的建筑就是拖整组）
    private enum BoxDragKind { case box, group }
    @State private var boxDragKind: BoxDragKind? = nil
    @State private var boxDragStart: GridPoint? = nil
    @State private var boxDragCurrent: GridPoint? = nil
    @State private var groupDragDelta: GridPoint? = nil
    /// 拖动起点（网格坐标）和手指最近一次的全局坐标：画布自动滚动时手指不动，
    /// 要靠网格自己的全局位置变化重新换算手指落在哪一格
    @State private var boxDragStartLocal: CGPoint? = nil
    @State private var boxDragFingerGlobal: CGPoint? = nil
    /// 网格在屏幕上的位置：滚动时每帧都变，放在引用类型里改，不触发重新计算视图
    @State private var gridFrameBox = GridFrameBox()
    /// 每帧画线前重算一次的端口方向表（引用类型，画线时只读，不触发重算视图）
    @State private var portEnds = PortEndDirections()
    /// 拖布局虚影：起点时虚影的 origin 和手指（网格坐标）
    @State private var placementDragStartOrigin: GridPoint? = nil
    @State private var placementDragStartLocal: CGPoint? = nil
    private var gridGlobalFrame: CGRect { gridFrameBox.frame }
    private let groupColor = Color(red: 0.3, green: 0.85, blue: 0.95)

    private var cols: Int { vm.layout.mapType.rules.gridCols }
    private var rows: Int { vm.layout.mapType.rules.gridRows }

    var body: some View {
        ZStack(alignment: .topLeading) {
            gridLines
            pumpZoneLayer
            powerRangeLayer
            beltsLayer
            buildingsLayer
            portsLayer
            dragPreview
            beltStartMarker
            portSnapHighlight
            boxSelectionOverlay
            gestureOverlay
            repositionHandle
            placementOverlay
        }
        .frame(width: CGFloat(cols) * cellSize, height: CGFloat(rows) * cellSize)
        // 画在网格外面，用 background 不改变网格自身尺寸和坐标
        .background(alignment: .topLeading) { warehouseLineDecoration }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            gridFrameBox.frame = frame
            if boxDragKind != nil { updateBoxDrag() }
            if placementDragStartOrigin != nil { updatePlacementDrag() }
        }
        .background(FactoryCanvasPalette.background)
        .onAppear { updateBeltAnimation() }
        .onChange(of: reduceMotion) { _, _ in updateBeltAnimation() }
    }

    private func updateBeltAnimation() {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { beltAnimPhase = 0 }
        if !reduceMotion {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { beltAnimPhase = 20 }
        }
    }

    // MARK: - 水泵区：基地右侧一条，只放水泵/气泵
    @ViewBuilder
    private var pumpZoneLayer: some View {
        let rules = vm.layout.mapType.rules
        if rules.pumpZoneWidth > 0 {
            let x = CGFloat(rules.baseCols) * cellSize
            let width = CGFloat(rules.pumpZoneWidth) * cellSize
            let height = CGFloat(rows) * cellSize
            ZStack(alignment: .top) {
                Rectangle().fill(AppColors.info.opacity(0.08))
                if cellSize >= 18 {
                    Text(String(localized: "水泵区 · 默认通电"))
                        .font(.system(size: max(8, min(cellSize * 0.32, 13)), weight: .semibold))
                        .foregroundStyle(AppColors.info)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .padding(.top, cellSize * 0.3)
                        .padding(.horizontal, 2)
                }
            }
            .frame(width: width, height: height)
            .overlay(alignment: .leading) {
                // 基地边界：虚线
                Path { p in
                    p.move(to: .zero)
                    p.addLine(to: CGPoint(x: 0, y: height))
                }
                .stroke(AppColors.info, style: StrokeStyle(lineWidth: max(1.5, cellSize * 0.05), dash: [cellSize * 0.4, cellSize * 0.25]))
            }
            .offset(x: x)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    // MARK: - 四号谷地外围的仓库存取线（示意）
    /// 四号谷地的取货口/存货口贴着基地上边、左边放，这两条边外面就是仓库存取线。
    /// 这里只画个示意（尺寸照武陵：源桩 4×4、基段 4×8），不占格子、不参与计算
    static let warehouseLineDepth = 4

    @ViewBuilder
    private var warehouseLineDecoration: some View {
        if case .perimeter(let edges) = vm.layout.mapType.rules.warehouseLine {
            let depth = CGFloat(Self.warehouseLineDepth)
            let top = edges.contains(.up), left = edges.contains(.left)
            Canvas { context, _ in
                let c = cellSize
                func module(_ rect: CGRect, isSource: Bool) {
                    let r = rect.insetBy(dx: c * 0.08, dy: c * 0.08)
                    context.fill(Path(r), with: .color(FactoryCanvasPalette.building))
                    context.stroke(Path(r), with: .color(FactoryCanvasPalette.ink.opacity(0.85)), lineWidth: max(1, c * 0.05))
                    if isSource {
                        let d = min(r.width, r.height) * 0.5
                        let ring = CGRect(x: r.midX - d / 2, y: r.midY - d / 2, width: d, height: d)
                        context.stroke(Path(ellipseIn: ring), with: .color(FactoryCanvasPalette.structure), lineWidth: max(1, c * 0.05))
                        context.fill(Path(ellipseIn: ring.insetBy(dx: d * 0.3, dy: d * 0.3)), with: .color(FactoryCanvasPalette.structure))
                        return
                    }
                    // 基段：沿长边两条导轨 + 中间分隔
                    let horizontal = r.width > r.height
                    var rails = Path()
                    for f in [0.3, 0.7] as [CGFloat] {
                        if horizontal {
                            rails.move(to: CGPoint(x: r.minX + c * 0.3, y: r.minY + r.height * f))
                            rails.addLine(to: CGPoint(x: r.maxX - c * 0.3, y: r.minY + r.height * f))
                        } else {
                            rails.move(to: CGPoint(x: r.minX + r.width * f, y: r.minY + c * 0.3))
                            rails.addLine(to: CGPoint(x: r.minX + r.width * f, y: r.maxY - c * 0.3))
                        }
                    }
                    context.stroke(rails, with: .color(FactoryCanvasPalette.structure.opacity(0.6)), lineWidth: max(0.75, c * 0.03))
                    if c >= 18 {
                        let label = Text(String(localized: "仓库存取线"))
                            .font(.system(size: min(c * 0.45, 14), weight: .semibold))
                            .foregroundColor(FactoryCanvasPalette.secondaryInk)
                        context.draw(label, at: CGPoint(x: r.midX, y: r.midY))
                    }
                }
                let origin = CGPoint(x: left ? depth * c : 0, y: top ? depth * c : 0)
                if top && left {
                    module(CGRect(x: 0, y: 0, width: depth * c, height: depth * c), isSource: true)
                }
                if top {
                    for col in stride(from: 0, to: cols, by: 8) {
                        let len = CGFloat(min(8, cols - col))
                        module(CGRect(x: origin.x + CGFloat(col) * c, y: 0, width: len * c, height: depth * c), isSource: false)
                    }
                }
                if left {
                    for row in stride(from: 0, to: rows, by: 8) {
                        let len = CGFloat(min(8, rows - row))
                        module(CGRect(x: 0, y: origin.y + CGFloat(row) * c, width: depth * c, height: len * c), isSource: false)
                    }
                }
            }
            .frame(width: CGFloat(cols) * cellSize + (left ? depth * cellSize : 0),
                   height: CGFloat(rows) * cellSize + (top ? depth * cellSize : 0))
            .offset(x: left ? -depth * cellSize : 0, y: top ? -depth * cellSize : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    // MARK: - 网格线
    private var gridLines: some View {
        Canvas { context, size in
            var path = Path()
            for c in 0...cols {
                let x = CGFloat(c) * cellSize
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            for r in 0...rows {
                let y = CGFloat(r) * cellSize
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path,
                with: .color(FactoryCanvasPalette.minorGrid),
                lineWidth: 0.5)

            var thickPath = Path()
            for c in stride(from: 0, through: cols, by: 5) {
                let x = CGFloat(c) * cellSize
                thickPath.move(to: CGPoint(x: x, y: 0))
                thickPath.addLine(to: CGPoint(x: x, y: size.height))
            }
            for r in stride(from: 0, through: rows, by: 5) {
                let y = CGFloat(r) * cellSize
                thickPath.move(to: CGPoint(x: 0, y: y))
                thickPath.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(thickPath,
                with: .color(FactoryCanvasPalette.majorGrid),
                lineWidth: 1)
        }
        .frame(width: CGFloat(cols) * cellSize, height: CGFloat(rows) * cellSize)
    }

    // 工程图线路：浅黄物流带 / 中性管道，阻塞和利用率仍有独立状态色。
    private let selectionColor = FactoryCanvasPalette.selection
    private let beltColor      = FactoryCanvasPalette.belt
    private let pipeColor      = FactoryCanvasPalette.pipe
    private let beltBlockedColor = Color.red

    /// 同一格、同一轴上如果传送带和管道都经过（平行走线），管道会缩细叠在传送带上面显示，
    /// 不用左右分开占位——两者物理上本来就不在同一高度，缩细叠加比硬挤在同一格宽度里更接近实际，
    /// 也不需要处理拐弯时两条平行线的偏移几何（那套逻辑之前出过畸变）
    private func sharedAxisKeys(_ segs: [BeltSegment]) -> Set<String> {
        var typesByCellAxis: [String: Set<LineType>] = [:]
        for seg in segs {
            let key = "\(seg.cell.col),\(seg.cell.row),\(seg.axis.rawValue)"
            typesByCellAxis[key, default: []].insert(seg.lineType)
        }
        return Set(typesByCellAxis.filter { $0.value.count > 1 }.keys)
    }

    // MARK: - 传送带/管道层
    private var beltsLayer: some View {
        Canvas { context, size in
            refreshPortEnds()
            // 物流桥/管道桥是特意留给线穿过去的交叉节点，不算挡路，排除在外，
            // 不然线一穿过自己触发生成的桥就会被判定成"撞到建筑"整条标红
            let occupied = vm.lineBlockingCellKeys()
            let allSegs = vm.layout.beltNetwork.allSegments
            let sharedKeys = sharedAxisKeys(allSegs + vm.beltPreviewSegments)

            // 传送带先画（打底），管道后画（叠在上面），保证共存时管道细线始终可见
            let utilization = vm.showUtilization
            for type in [LineType.belt, .pipe] {
                for belt in vm.layout.beltNetwork.belts where belt.lineType == type {
                    let level = utilization ? utilizationLevel(of: belt) : nil
                    let dimmed = vm.isDimmedByHighlight(belt: belt.id)
                    drawOneBelt(belt, occupied: occupied, sharedKeys: sharedKeys, isPreview: false,
                                alphaScale: (level == .idle ? 0.25 : 1) * (dimmed ? 0.18 : 1), context: &context)
                    if let level { drawUtilization(level, on: belt, context: &context) }
                }
            }

            // 拖拽预览
            if !vm.beltPreviewSegments.isEmpty {
                let existingDirKeys = Set(allSegs.map {
                    "\($0.cell.col),\($0.cell.row),\($0.axis.rawValue),\($0.toDir.col),\($0.toDir.row),\($0.lineType.rawValue)"
                })
                var previewBlockedSet = Set<String>()
                for seg in vm.beltPreviewSegments {
                    let cellKey = "\(seg.cell.col),\(seg.cell.row)"
                    let dirKey  = "\(cellKey),\(seg.axis.rawValue),\(seg.toDir.col),\(seg.toDir.row),\(seg.lineType.rawValue)"
                    if occupied.contains(cellKey) || existingDirKeys.contains(dirKey) {
                        previewBlockedSet.insert(cellKey)
                    }
                }
                drawBeltPath(segments: vm.beltPreviewSegments,
                             lineType: vm.activeLineType,
                             sharedKeys: sharedKeys,
                             blockedSet: previewBlockedSet,
                             isPreview: true, context: &context)
            }

            // 选中的线：沿中心线叠一条黄线，点中的那一格加框
            if let selected = vm.selectedBelt {
                let style = StrokeStyle(lineWidth: max(2, cellSize * 0.16), lineCap: .round, lineJoin: .round)
                drawChain(selected.segments, color: selectionColor, blockedColor: selectionColor,
                          blockedSet: [], style: style, radius: cellSize * 0.38, context: &context)
                if let cell = vm.selectedBeltCell {
                    let rect = CGRect(x: CGFloat(cell.col) * cellSize, y: CGFloat(cell.row) * cellSize,
                                      width: cellSize, height: cellSize)
                    context.stroke(Path(rect), with: .color(selectionColor), lineWidth: max(2, cellSize * 0.06))
                }
            }

            // 框选选中的线：沿中心线叠一条青线
            if !vm.groupBeltSelection.isEmpty {
                let style = StrokeStyle(lineWidth: max(2, cellSize * 0.16), lineCap: .round, lineJoin: .round)
                for belt in vm.layout.beltNetwork.belts where vm.groupBeltSelection.contains(belt.id) {
                    drawChain(belt.segments, color: groupColor, blockedColor: groupColor,
                              blockedSet: [], style: style, radius: cellSize * 0.38, context: &context)
                }
            }

            // 起点光标：整格高亮边框
            if let start = vm.beltStart {
                let x = CGFloat(start.col) * cellSize
                let y = CGFloat(start.row) * cellSize
                let rect = CGRect(x: x, y: y, width: cellSize, height: cellSize)
                var box = Path()
                box.addRect(rect)
                context.stroke(box, with: .color(beltColor), lineWidth: 3)
                // 内部半透明填充
                context.fill(box, with: .color(beltColor.opacity(0.25)))
            }
        }
        .frame(width: CGFloat(cols) * cellSize, height: CGFloat(rows) * cellSize)
    }

    private func drawOneBelt(_ belt: Belt, occupied: Set<String>, sharedKeys: Set<String>,
                             isPreview: Bool, alphaScale: Double = 1, context: inout GraphicsContext) {
        let blockedSet = Set(belt.segments
            .filter { occupied.contains("\($0.cell.col),\($0.cell.row)") }
            .map { "\($0.cell.col),\($0.cell.row)" })
        drawBeltPath(segments: belt.segments, lineType: belt.lineType,
                     sharedKeys: sharedKeys, blockedSet: blockedSet,
                     isPreview: isPreview, alphaScale: alphaScale, context: &context)
    }

    // MARK: - 利用率视图
    enum UtilizationLevel: Equatable {
        case idle                 // 没东西走（包括线头没接出口的线）
        case partial(Double)      // 没跑满，带百分比
        case full                 // 跑满
        case overCapacity         // 上游想塞的比上限多，被限流（瓶颈）
    }

    private func utilizationLevel(of belt: Belt) -> UtilizationLevel {
        guard let flow = vm.stats.beltFlows[belt.id], flow.total > 1e-6, flow.capacity > 0 else { return .idle }
        if flow.isOverCapacity { return .overCapacity }
        let ratio = flow.total / flow.capacity
        return ratio >= 0.995 ? .full : .partial(ratio)
    }

    static let utilizationFullColor = Color(red: 0.35, green: 0.95, blue: 0.45)
    static let utilizationOverColor = Color(red: 1.0, green: 0.25, blue: 0.2)

    /// 分段细线表示运行状态，部分负载标牌按真实比例显示刻度与百分比。
    private func drawUtilization(_ level: UtilizationLevel, on belt: Belt, context: inout GraphicsContext) {
        let traceWidth = max(1.5, cellSize * 0.12)
        let style = StrokeStyle(lineWidth: traceWidth, lineCap: .butt, lineJoin: .round,
                                dash: [max(2, cellSize * 0.18), max(1, cellSize * 0.06)])
        switch level {
        case .full:
            drawChain(belt.segments, color: Self.utilizationFullColor, blockedColor: Self.utilizationFullColor,
                      blockedSet: [], style: style, radius: cellSize * 0.38, context: &context)
        case .overCapacity:
            drawChain(belt.segments, color: Self.utilizationOverColor, blockedColor: Self.utilizationOverColor,
                      blockedSet: [], style: style, radius: cellSize * 0.38, context: &context)
        case .partial(let ratio):
            drawChain(belt.segments, color: AppColors.info.opacity(0.7), blockedColor: AppColors.info,
                      blockedSet: [], style: style, radius: cellSize * 0.38, context: &context)
            drawUtilizationMeter(ratio, on: belt, context: &context)
        case .idle:
            break
        }
    }

    private func drawUtilizationMeter(_ ratio: Double, on belt: Belt, context: inout GraphicsContext) {
        guard cellSize >= 16, !belt.segments.isEmpty else { return }
        let center = cellCenter(belt.segments[belt.segments.count / 2].cell)
        let width = max(28, cellSize * 1.1)
        let height = max(18, cellSize * 0.62)
        let box = CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
        context.fill(Path(box), with: .color(AppColors.surface))
        context.stroke(Path(box), with: .color(FactoryCanvasPalette.structure), lineWidth: 0.75)

        // 十格刻度仅映射已有 ratio；绘制层不改变利用率计算或满载判定。
        let gap: CGFloat = 1
        let inset: CGFloat = 3
        let segmentWidth = (width - inset * 2 - gap * 9) / 10
        let amount = max(0, min(1, ratio)) * 10
        for index in 0..<10 {
            let segment = CGRect(x: box.minX + inset + CGFloat(index) * (segmentWidth + gap),
                                 y: box.minY + inset, width: segmentWidth, height: max(2, height * 0.12))
            context.fill(Path(segment), with: .color(FactoryCanvasPalette.structure.opacity(0.2)))
            let fill = max(0, min(1, amount - Double(index)))
            if fill > 0 {
                let filled = CGRect(x: segment.minX, y: segment.minY,
                                    width: segment.width * CGFloat(fill), height: segment.height)
                context.fill(Path(filled), with: .color(AppColors.info))
            }
        }
        let text = Text("\(Int((ratio * 100).rounded()))%")
            .font(.system(size: max(8, min(cellSize * 0.28, 14)), weight: .semibold, design: .monospaced))
            .foregroundColor(FactoryCanvasPalette.ink)
        context.draw(text, at: CGPoint(x: center.x, y: center.y + height * 0.12))
    }

    /// 传送带/管道渲染：Belt.segments 本身已有序，直接画圆角折线，不需要重新串链
    private func drawBeltPath(segments: [BeltSegment],
                              lineType: LineType,
                              sharedKeys: Set<String>,
                              blockedSet: Set<String>,
                              isPreview: Bool,
                              alphaScale: Double = 1,
                              context: inout GraphicsContext) {
        guard !segments.isEmpty else { return }

        // 只有管道会在共存时缩细（传送带外观始终不变，管道叠在它上面显示）
        let isShared = segments.contains {
            sharedKeys.contains("\($0.cell.col),\($0.cell.row),\($0.axis.rawValue)")
        }
        let widthScale: CGFloat = (isShared && lineType == .pipe) ? 0.34 : 1.0
        let baseColor = lineType == .belt ? beltColor : pipeColor

        let lineW  = cellSize * widthScale
        let radius = cellSize * 0.38 * widthScale
        let alpha: Double = (isPreview ? 0.45 : 1.0) * alphaScale
        let dashPattern: [CGFloat] = isPreview ? [cellSize * 0.7, cellSize * 0.3] : []

        // 背景层：暗色
        let bgStyle = StrokeStyle(lineWidth: lineW, lineCap: .butt, lineJoin: .miter)
        drawChain(segments, color: baseColor.opacity(alpha * 0.55),
                  blockedColor: beltBlockedColor.opacity(alpha * 0.55),
                  blockedSet: blockedSet, style: bgStyle, radius: radius, context: &context)

        // 前景层：稍窄亮色
        let fgStyle = StrokeStyle(lineWidth: lineW * 0.55, lineCap: .butt, lineJoin: .miter,
                                  dash: dashPattern,
                                  dashPhase: isPreview ? 0 : beltAnimPhase * cellSize * 0.05)
        drawChain(segments, color: baseColor.opacity(alpha),
                  blockedColor: beltBlockedColor.opacity(alpha),
                  blockedSet: blockedSet, style: fgStyle, radius: radius, context: &context)

        // 方向箭头沿用真实流向，以较小深色 / 反色箭头呈现工程图样式。
        for seg in segments {
            let c = cellCenter(seg.cell)
            let cellKey = "\(seg.cell.col),\(seg.cell.row)"
            let isBlocked = blockedSet.contains(cellKey)
            // 箭头大小约为格子的 18%，管道缩细时箭头也跟着小一号但不要太小看不清
            let arrowSize = cellSize * 0.18 * max(widthScale, 0.55)
            drawArrow(at: c, dir: seg.toDir, size: arrowSize,
                      color: (lineType == .belt ? FactoryCanvasPalette.beltArrow : FactoryCanvasPalette.pipeArrow)
                        .opacity(isBlocked ? 0.5 : alpha * 0.9),
                      context: &context)
            // 阻碍红叉
            if isBlocked && !isPreview {
                let s = cellSize * 0.18
                var cross = Path()
                cross.move(to: CGPoint(x: c.x - s, y: c.y - s))
                cross.addLine(to: CGPoint(x: c.x + s, y: c.y + s))
                cross.move(to: CGPoint(x: c.x + s, y: c.y - s))
                cross.addLine(to: CGPoint(x: c.x - s, y: c.y + s))
                context.stroke(cross, with: .color(.red), lineWidth: 3)
            }
        }
    }


    /// 画单条 chain 的圆角路径
    /// - 线宽 = 格子宽（或缩细后的宽度），端点对齐格子边缘
    /// - 拐角处用 quadCurve 做圆弧
    /// - 传送带和管道各画各的中心线，互不偏移；共存时靠管道整体缩细叠加在上面区分，
    ///   所以这里不需要处理"两条平行线在拐弯处怎么错开"这种问题
    private func drawChain(_ chain: [BeltSegment],
                           color: Color,
                           blockedColor: Color,
                           blockedSet: Set<String>,
                           style: StrokeStyle,
                           radius: CGFloat,
                           context: inout GraphicsContext) {
        guard !chain.isEmpty else { return }

        // 合并同格拐角段为关键点
        struct KP { var cell: GridPoint; var inDir: GridPoint; var outDir: GridPoint; var blocked: Bool }
        var kps: [KP] = []
        var i = 0
        while i < chain.count {
            let seg = chain[i]
            let blocked = blockedSet.contains("\(seg.cell.col),\(seg.cell.row)")
            if i + 1 < chain.count && chain[i + 1].cell == seg.cell {
                kps.append(KP(cell: seg.cell, inDir: seg.fromDir, outDir: chain[i+1].toDir, blocked: blocked))
                i += 2
            } else {
                kps.append(KP(cell: seg.cell, inDir: seg.fromDir, outDir: seg.toDir, blocked: blocked))
                i += 1
            }
        }
        guard !kps.isEmpty else { return }

        // 线头接在出口外面、线尾接在入口外面时，按端口朝向画这一格：线从侧面拉出去也会先从口里出来再拐弯，
        // 一眼能看出是接在这个口上的
        // 候选方向里去掉跟线的实际走向相反的（线不会掉头钻回自己出来的口），优先用线自己存的方向
        let kindKey = chain[0].lineType == .belt ? PortKind.item.rawValue : PortKind.pipe.rawValue
        func pick(_ candidates: [GridPoint]?, stored: GridPoint, notOpposite travel: GridPoint) -> GridPoint? {
            let ok = (candidates ?? []).filter { $0.col != -travel.col || $0.row != -travel.row }
            return ok.contains(stored) ? stored : ok.first
        }
        let first = kps[0], last = kps[kps.count - 1]
        if let dir = pick(portEnds.headDir["\(first.cell.col),\(first.cell.row),\(kindKey)"],
                          stored: first.inDir, notOpposite: first.outDir) {
            kps[0].inDir = dir
        }
        if let dir = pick(portEnds.tailDir["\(last.cell.col),\(last.cell.row),\(kindKey)"],
                          stored: last.outDir, notOpposite: kps[kps.count - 1].inDir) {
            kps[kps.count - 1].outDir = dir
        }

        // 按格子实际位置切成几段相邻的连续走线：衔接到侧边的线存的方向和真实相邻关系对不上，
        // 只看存的方向会把两个拐点直接连成斜线；中间断开的格子则单独起笔
        var runs: [[KP]] = [[kps[0]]]
        for kp in kps.dropFirst() {
            let prev = runs[runs.count - 1].last!.cell
            if abs(kp.cell.col - prev.col) + abs(kp.cell.row - prev.row) == 1 {
                runs[runs.count - 1].append(kp)
            } else {
                runs.append([kp])
            }
        }

        var path = Path()
        for run in runs { addRun(run.map { (cell: $0.cell, inDir: $0.inDir, outDir: $0.outDir) }, radius: radius, to: &path) }

        // 如果有阻碍格则用阻碍色，否则正常色
        let hasBlocked = kps.contains { $0.blocked }
        context.stroke(path, with: .color(hasBlocked ? blockedColor : color), style: style)
    }

    /// 一段相邻格子的圆角折线。中间格的进出方向取相邻格的真实位置差，只有首尾用存的方向，
    /// 所以相邻折点一定同行或同列，不会出现斜线。
    /// butt cap 不延伸，起点/终点设在首尾格的入口/出口边缘。
    private func addRun(_ run: [(cell: GridPoint, inDir: GridPoint, outDir: GridPoint)],
                        radius: CGFloat, to path: inout Path) {
        func step(_ a: GridPoint, _ b: GridPoint) -> GridPoint { GridPoint(col: b.col - a.col, row: b.row - a.row) }
        let first = run[0]; let last = run[run.count - 1]
        let firstCenter = cellCenter(first.cell); let lastCenter = cellCenter(last.cell)
        var pts: [CGPoint] = []
        pts.append(CGPoint(
            x: firstCenter.x - CGFloat(first.inDir.col) * cellSize * 0.5,
            y: firstCenter.y - CGFloat(first.inDir.row) * cellSize * 0.5))
        // 只加方向变化格的中心（直线段的中间格连起来就是直线）
        for idx in 0..<run.count {
            let prevDir = idx == 0 ? run[idx].inDir : step(run[idx - 1].cell, run[idx].cell)
            let nextDir = idx == run.count - 1 ? run[idx].outDir : step(run[idx].cell, run[idx + 1].cell)
            if prevDir != nextDir { pts.append(cellCenter(run[idx].cell)) }
        }
        pts.append(CGPoint(
            x: lastCenter.x + CGFloat(last.outDir.col) * cellSize * 0.5,
            y: lastCenter.y + CGFloat(last.outDir.row) * cellSize * 0.5))

        path.move(to: pts[0])
        for j in 1..<pts.count - 1 {
            let prev = pts[j-1]; let curr = pts[j]; let next = pts[j+1]
            let d1 = CGPoint(x: curr.x - prev.x, y: curr.y - prev.y)
            let d2 = CGPoint(x: next.x - curr.x, y: next.y - curr.y)
            let isCorner = (abs(d1.x) > 0.1) != (abs(d2.x) > 0.1)
            let lenIn = dist(prev, curr); let lenOut = dist(curr, next)
            if isCorner, lenIn > 0.1, lenOut > 0.1 {
                let rIn  = min(radius, lenIn  * 0.48)
                let rOut = min(radius, lenOut * 0.48)
                path.addLine(to: CGPoint(x: curr.x - d1.x/lenIn*rIn,  y: curr.y - d1.y/lenIn*rIn))
                path.addQuadCurve(
                    to: CGPoint(x: curr.x + d2.x/lenOut*rOut, y: curr.y + d2.y/lenOut*rOut),
                    control: curr)
            } else {
                path.addLine(to: curr)
            }
        }
        path.addLine(to: pts[pts.count - 1])
    }

    private func refreshPortEnds() {
        var head: [String: [GridPoint]] = [:], tail: [String: [GridPoint]] = [:]
        for placed in vm.layout.buildings {
            guard let def = BuildingDefinition.find(placed.definitionID) else { continue }
            for port in def.ports {
                let (cell, facing) = port.resolvedPosition(placed: placed, definition: def)
                let out = facing.outputOffset
                let key = "\(cell.col + out.col),\(cell.row + out.row),\(port.kind.rawValue)"
                if port.ioDirection == .output {
                    head[key, default: []].append(out)
                } else {
                    tail[key, default: []].append(GridPoint(col: -out.col, row: -out.row))
                }
            }
        }
        portEnds.headDir = head
        portEnds.tailDir = tail
    }

    private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x; let dy = b.y - a.y
        return sqrt(dx * dx + dy * dy)
    }

    private func occupiedCellKeys() -> Set<String> {
        Set(vm.layout.buildings.flatMap { placed -> [String] in
            guard let def = BuildingDefinition.find(placed.definitionID) else { return [] }
            return placed.occupiedCells(definition: def).map { "\($0.col),\($0.row)" }
        })
    }

    /// 格子中央方向箭头：实心宽三角，清晰可辨
    private func drawArrow(at center: CGPoint, dir: GridPoint,
                           size: CGFloat, color: Color,
                           context: inout GraphicsContext) {
        let dx = CGFloat(dir.col)
        let dy = CGFloat(dir.row)
        guard dx != 0 || dy != 0 else { return }
        let perp = CGPoint(x: -dy, y: dx)
        // 箭头：顶点在出口方向，底边在入口方向，宽度约为格子 50%
        let tip  = CGPoint(x: center.x + dx * size * 0.9,  y: center.y + dy * size * 0.9)
        let baseL = CGPoint(x: center.x - dx * size * 0.5 + perp.x * size * 0.75,
                             y: center.y - dy * size * 0.5 + perp.y * size * 0.75)
        let baseR = CGPoint(x: center.x - dx * size * 0.5 - perp.x * size * 0.75,
                             y: center.y - dy * size * 0.5 - perp.y * size * 0.75)
        var p = Path()
        p.move(to: tip)
        p.addLine(to: baseL)
        p.addLine(to: baseR)
        p.closeSubpath()
        context.fill(p, with: .color(color))
    }

    // MARK: - 建筑层
    private var buildingsLayer: some View {
        ForEach(vm.layout.buildings) { placed in
            if let def = BuildingDefinition.find(placed.definitionID) {
                buildingCard(placed: placed, def: def)
            }
        }
    }

    private func buildingCard(placed: PlacedBuilding, def: BuildingDefinition) -> some View {
        let size = placed.effectiveSize(definition: def)
        let w = CGFloat(size.width) * cellSize
        let h = CGFloat(size.height) * cellSize
        let x = CGFloat(placed.origin.col) * cellSize
        let y = CGFloat(placed.origin.row) * cellSize
        let isSelected = placed.id == vm.selectedBuildingID
        let isGroupMember = vm.groupSelection.contains(placed.id)
        let machineStatus = vm.stats.machineStates.first { $0.id == placed.id }?.status
        let displayedStatus = placed.isActive ? machineStatus : .inactive

        // 仓库取货口/存货口这类只有 1 格厚的长条形建筑，塞不下竖排的图标+名字+材料+朝向
        // 四行文字（超出边框但没裁切，看着就像"整个建筑变大了一圈"），改成横向紧凑排布
        let isThin = size.width == 1 || size.height == 1

        // rotation 记录的是端口"安装朝向"，出口的物流方向跟它一致，但入口（比如存货口）
        // 物流方向其实是反过来的（东西是从外面流进来的）——卡片上这个箭头是给人看流向的，
        // 入口类建筑要显示 rotation 的反方向，不然会跟旁边传送带的箭头对不上、看着像反了
        let flowSymbol = (def.id == BuildingDefinition.warehouseInletID
                          ? placed.rotation.opposite : placed.rotation).symbol

        // 名字下面那行设置：取货口/暗管出口显示出什么，准入口设了过滤才显示放行什么
        let settingLabel: (text: String, isSet: Bool)?
        let hasMapConflict = vm.stats.mapConflicts[placed.id] != nil
        if hasMapConflict {
            settingLabel = (String(localized: "地图不支持"), false)
        } else if def.choosesOutletMaterial {
            let name = placed.outletMaterialID.flatMap(ItemCatalog.name(for:))
            settingLabel = (name.map(DisplayName.item) ?? String(localized: "未设置"), name != nil)
        } else if def.id == "log_conditioner" || def.id == "log_pipe_conditioner",
                  let name = placed.filterItemID.flatMap(ItemCatalog.name(for:)) {
            settingLabel = (DisplayName.item(name), true)
        } else {
            settingLabel = nil
        }

        let materialName = settingLabel?.isSet == true ? settingLabel?.text : nil
        // 当前配方的主产物：画在机身中央（反应池同时跑多条配方，不显示）；
        // 缩到接近最小、或图标本身小到看不清时换回类别图标
        let showsProduct = cellSize >= Self.productIconMinCellSize && min(w, h) * 0.42 >= 14
        let productName: String? = def.isMultiRecipeMachine || !showsProduct ? nil
            : placed.selectedRecipeID.flatMap { id in vm.availableRecipes(for: def).first { $0.id == id } }?.outputs.first?.name
        return ZStack {
            if let node = Self.logisticsNode(for: def.id) {
                // 分流器/汇流器/桥/准入口：不画通用卡片和端口槽，直接画分叉/汇合/立交/闸门符号
                logisticsSymbol(node, placed: placed, def: def)
                    .overlay(alignment: .bottomTrailing) {
                        // 准入口设了过滤：右下角小图标显示只放行什么
                        if node == .gate, let name = placed.filterItemID.flatMap(ItemCatalog.name(for:)), w >= 24 {
                            ItemIcon(name: name, size: w * 0.34)
                                .background(FactoryCanvasPalette.badgeFill, in: Circle())
                                .allowsHitTesting(false)
                        }
                    }
                if hasMapConflict {
                    Rectangle().stroke(AppColors.error, lineWidth: 2.5)
                }
            } else {
                FactoryBuildingShell(circularInset: def.powerRange != nil && size.width == size.height)
                if hasMapConflict {
                    Rectangle().stroke(AppColors.error, lineWidth: 2.5)
                }
                if isThin {
                    HStack(spacing: 4) {
                        buildingSymbol(for: def, material: materialName, size: min(w, h) * 0.48)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: def.displayName).minimumScaleFactor(0.35)
                                .font(.system(size: min(w, h) * 0.32, weight: .bold, design: .monospaced))
                                .foregroundColor(FactoryCanvasPalette.ink).lineLimit(1)
                            if let setting = settingLabel {
                                Text(setting.text)
                                    .font(.system(size: min(w, h) * 0.26, design: .monospaced))
                                    .foregroundColor(hasMapConflict ? Color(red: 0.95, green: 0.35, blue: 0.3)
                                                     : setting.isSet ? AppColors.success
                                                     : FactoryCanvasPalette.secondaryInk)
                                    .lineLimit(1)
                            }
                        }
                        Text(flowSymbol)
                            .font(.system(size: min(w, h) * 0.4))
                            .foregroundColor(FactoryCanvasPalette.secondaryInk)
                    }
                    .padding(4)
                    .minimumScaleFactor(0.6)
                } else if let productName {
                    VStack(spacing: 2) {
                        itemBadge(productName, size: min(w, h) * 0.42)
                            .opacity(displayedStatus == .running ? 1 : 0.55)
                        Text(verbatim: def.displayName).minimumScaleFactor(0.35)
                            .font(.system(size: min(w, h) * 0.11, weight: .bold, design: .monospaced))
                            .foregroundColor(FactoryCanvasPalette.secondaryInk).lineLimit(1)
                    }.padding(4)
                } else {
                    VStack(spacing: 3) {
                        buildingSymbol(for: def, material: materialName, size: min(w, h) * 0.28)
                        Text(verbatim: def.displayName).minimumScaleFactor(0.35)
                            .font(.system(size: min(w, h) * 0.16, weight: .bold, design: .monospaced))
                            .foregroundColor(FactoryCanvasPalette.ink).lineLimit(1)
                        if let setting = settingLabel {
                            Text(setting.text)
                                .font(.system(size: min(w, h) * 0.14, design: .monospaced))
                                .foregroundColor(hasMapConflict ? Color(red: 0.95, green: 0.35, blue: 0.3)
                                                 : setting.isSet ? AppColors.success
                                                 : FactoryCanvasPalette.secondaryInk)
                                .lineLimit(1)
                        }
                        Text(flowSymbol)
                            .font(.system(size: min(w, h) * 0.18))
                            .foregroundColor(FactoryCanvasPalette.secondaryInk)
                    }.padding(4)
                }
            }
            if isSelected {
                // 选中框：整圈黄色粗边，缩小看全图时也一眼能找到
                Rectangle()
                    .stroke(FactoryCanvasPalette.selection, lineWidth: max(2, cellSize * 0.08))
                    .allowsHitTesting(false)
            }
            if isGroupMember {
                // 框选选中：青色粗边 + 淡青填充，跟单选的黄色区分开
                Rectangle().fill(groupColor.opacity(0.18)).allowsHitTesting(false)
                Rectangle()
                    .stroke(groupColor, lineWidth: max(2, cellSize * 0.08))
                    .allowsHitTesting(false)
            }
        }
        .frame(width: w, height: h)
        .overlay(alignment: .topLeading) {
            // 不在供电桩范围内：左上角断电图标，不用点开也看得到
            if placed.isActive && vm.stats.unpoweredIDs.contains(placed.id) {
                Image(systemName: "bolt.slash.fill")
                    .font(.system(size: max(9, min(min(w, h) * 0.22, 18)), weight: .bold))
                    .foregroundColor(Color(red: 1.0, green: 0.8, blue: 0.0))
                    .padding(3)
                    .background(Color.black.opacity(0.55))
                    .padding(3)
                    .accessibilityLabel(String(localized: "未通电"))
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topTrailing) {
            if let displayedStatus {
                Circle()
                    .fill(statusColor(displayedStatus))
                    .overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 1))
                    .frame(width: 8, height: 8)
                    .padding(4)
                    .accessibilityLabel(displayedStatus.displayLabel)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(def.displayName)
        .accessibilityValue([displayedStatus?.displayLabel, settingLabel?.text].compactMap { $0 }.joined(separator: "，"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(String(localized: "双击选择建筑"))
        .accessibilityAction {
            vm.editMode = .select
            vm.selectedBuildingID = placed.id
        }
        .opacity((placed.isActive ? 1 : 0.45) * (vm.isDimmedByHighlight(building: placed.id) ? 0.22 : 1))
        .clipped()
        .offset(x: x, y: y)
    }

    @ViewBuilder
    private func buildingSymbol(for def: BuildingDefinition, material: String?, size: CGFloat) -> some View {
        if let material {
            itemBadge(material, size: size)
        } else {
            Image(systemName: def.category.icon)
                .font(.system(size: size * 0.8, weight: .medium))
                .foregroundStyle(FactoryCanvasPalette.ink)
                .frame(width: size, height: size)
        }
    }

    /// 低于这个格子尺寸（缩到接近最小 16）不画产物图标
    static let productIconMinCellSize: CGFloat = 20

    /// 官方蓝图式物品徽章：深色圆底 + 蓝色细圈
    private func itemBadge(_ name: String, size: CGFloat) -> some View {
        ItemIcon(name: name, size: size * 0.78)
            .frame(width: size, height: size)
            .background(FactoryCanvasPalette.badgeFill, in: Circle())
            .overlay(Circle().stroke(FactoryCanvasPalette.badgeRing, lineWidth: max(1, size * 0.05)))
    }

    private func statusColor(_ status: FlowSimulator.MachineStatus) -> Color {
        switch status {
        case .running: return .green
        case .blocked: return .red
        case .starved: return .orange
        case .inactive, .noRecipe: return .gray
        }
    }

    // MARK: - 物流节点符号
    enum LogisticsNode { case splitter, converger, bridge, gate }

    static func logisticsNode(for id: String) -> LogisticsNode? {
        switch id {
        case "log_splitter", "log_pipe_splitter": return .splitter
        case "log_converger", "log_pipe_converger": return .converger
        case "log_connector", "log_pipe_connector": return .bridge
        case "log_conditioner", "log_pipe_conditioner": return .gate
        default: return nil
        }
    }

    /// 1×1 物流节点的专用符号：分流器 1 进 3 出（中间菱形）、汇流器 3 进 1 出（中间圆点）、
    /// 物流桥十字立交（竖的从横的上面跨过去）、准入口直通加一道闸门。
    /// 车道颜色跟线走（传送带黄、管道深色），接上线的方向实色，没接的变淡
    private func logisticsSymbol(_ node: LogisticsNode, placed: PlacedBuilding, def: BuildingDefinition) -> some View {
        let isPipe = def.id.contains("pipe")
        let lane = isPipe ? FactoryCanvasPalette.pipe : FactoryCanvasPalette.belt
        let arrow = isPipe ? FactoryCanvasPalette.pipeArrow : FactoryCanvasPalette.beltArrow
        let ports = def.ports.map { port -> (dir: GridPoint, isOutput: Bool, connected: Bool) in
            let facing = port.resolvedPosition(placed: placed, definition: def).facing
            return (facing.outputOffset, port.ioDirection == .output,
                    vm.isPortConnected(port, placed: placed, definition: def))
        }
        return Canvas { context, size in
            let s = min(size.width, size.height)
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let laneW = s * 0.3
            let body = CGRect(origin: .zero, size: size).insetBy(dx: s * 0.06, dy: s * 0.06)
            context.fill(Path(roundedRect: body, cornerRadius: s * 0.12), with: .color(FactoryCanvasPalette.building))
            context.stroke(Path(roundedRect: body, cornerRadius: s * 0.12),
                           with: .color(FactoryCanvasPalette.ink.opacity(0.8)), lineWidth: max(1, s * 0.04))
            func point(_ d: GridPoint, _ f: CGFloat) -> CGPoint {
                CGPoint(x: c.x + CGFloat(d.col) * s * 0.5 * f, y: c.y + CGFloat(d.row) * s * 0.5 * f)
            }
            func triangle(at p: CGPoint, toward d: GridPoint, size a: CGFloat) -> Path {
                let dx = CGFloat(d.col), dy = CGFloat(d.row)
                var t = Path()
                t.move(to: CGPoint(x: p.x + dx * a * 0.6, y: p.y + dy * a * 0.6))
                t.addLine(to: CGPoint(x: p.x - dx * a * 0.4 - dy * a * 0.55, y: p.y - dy * a * 0.4 + dx * a * 0.55))
                t.addLine(to: CGPoint(x: p.x - dx * a * 0.4 + dy * a * 0.55, y: p.y - dy * a * 0.4 - dx * a * 0.55))
                t.closeSubpath()
                return t
            }
            func laneSegment(_ d: GridPoint, connected: Bool) {
                var path = Path()
                path.move(to: c)
                path.addLine(to: point(d, 0.88))
                context.stroke(path, with: .color(lane.opacity(connected ? 1 : 0.35)),
                               style: StrokeStyle(lineWidth: laneW, lineCap: .butt))
            }

            switch node {
            case .splitter, .converger, .gate:
                for p in ports { laneSegment(p.dir, connected: p.connected) }
                for p in ports {
                    // 出口箭头在外侧朝外，入口箭头在里侧朝中心
                    let at = point(p.dir, p.isOutput ? 0.62 : 0.5)
                    let toward = p.isOutput ? p.dir : GridPoint(col: -p.dir.col, row: -p.dir.row)
                    context.fill(triangle(at: at, toward: toward, size: laneW * 0.8),
                                 with: .color(arrow.opacity(p.connected ? 1 : 0.5)))
                }
                let mark = s * 0.16
                let markRect = CGRect(x: c.x - mark / 2, y: c.y - mark / 2, width: mark, height: mark)
                switch node {
                case .splitter:
                    var diamond = Path()
                    diamond.move(to: CGPoint(x: c.x, y: markRect.minY))
                    diamond.addLine(to: CGPoint(x: markRect.maxX, y: c.y))
                    diamond.addLine(to: CGPoint(x: c.x, y: markRect.maxY))
                    diamond.addLine(to: CGPoint(x: markRect.minX, y: c.y))
                    diamond.closeSubpath()
                    context.fill(diamond, with: .color(FactoryCanvasPalette.ink))
                case .converger:
                    context.fill(Path(ellipseIn: markRect), with: .color(FactoryCanvasPalette.ink))
                default:
                    // 闸门：横跨车道的一道粗杠
                    let along = ports.first?.dir ?? GridPoint(col: 1, row: 0)
                    let perp = GridPoint(col: along.row, row: along.col)
                    var bar = Path()
                    bar.move(to: point(perp, 0.55))
                    bar.addLine(to: point(GridPoint(col: -perp.col, row: -perp.row), 0.55))
                    context.stroke(bar, with: .color(FactoryCanvasPalette.ink),
                                   style: StrokeStyle(lineWidth: max(1.5, s * 0.09), lineCap: .round))
                }
            case .bridge:
                // 横向车道在下，竖向车道从上面跨过去（两侧描边表示桥面）
                let horizontal = ports.contains { $0.dir.row == 0 && $0.connected }
                let vertical = ports.contains { $0.dir.col == 0 && $0.connected }
                var h = Path()
                h.move(to: point(GridPoint(col: -1, row: 0), 0.88)); h.addLine(to: point(GridPoint(col: 1, row: 0), 0.88))
                context.stroke(h, with: .color(lane.opacity(horizontal ? 1 : 0.35)), style: StrokeStyle(lineWidth: laneW))
                let deck = CGRect(x: c.x - laneW / 2, y: c.y - s * 0.44, width: laneW, height: s * 0.88)
                context.fill(Path(deck), with: .color(lane.opacity(vertical ? 1 : 0.35)))
                for x in [deck.minX, deck.maxX] {
                    var edge = Path()
                    edge.move(to: CGPoint(x: x, y: deck.minY)); edge.addLine(to: CGPoint(x: x, y: deck.maxY))
                    context.stroke(edge, with: .color(FactoryCanvasPalette.ink), lineWidth: max(1, s * 0.05))
                }
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - 端口标记层：依真实位置与方向绘制连接槽，实色短标记表示已连接
    /// 格子小于这个尺寸时端口槽已经看不清，不画（缩到看全图时省掉上千个小图形）
    static let portMinCellSize: CGFloat = 20

    /// 所有端口槽画在同一张 Canvas 里：原来每个端口一个视图，大布局有上千个，缩放松手重画时会卡
    private var portsLayer: some View {
        Canvas { context, _ in
            guard cellSize >= Self.portMinCellSize else { return }
            // 线头/线尾所在的格：端口外接格在这里面就算接上了（同 vm.isPortConnected）
            var lineEnds = Set<GridPoint>()
            for belt in vm.layout.beltNetwork.belts {
                if let head = belt.headCell { lineEnds.insert(head) }
                if let tail = belt.tailCell { lineEnds.insert(tail) }
            }
            for placed in vm.layout.buildings {
                guard let def = BuildingDefinition.find(placed.definitionID),
                      Self.logisticsNode(for: def.id) == nil else { continue }
                var layer = context
                if vm.isDimmedByHighlight(building: placed.id) { layer.opacity = 0.22 }
                for port in def.ports {
                    let (cell, facing) = port.resolvedPosition(placed: placed, definition: def)
                    let out = facing.outputOffset
                    let connected = lineEnds.contains(GridPoint(col: cell.col + out.col, row: cell.row + out.row))
                    drawPortSlot(port: port, cell: cell, facing: facing, connected: connected, context: &layer)
                }
            }
        }
        .frame(width: CGFloat(cols) * cellSize, height: CGFloat(rows) * cellSize)
        .allowsHitTesting(false)
    }

    /// 官方蓝图式端口槽：沿建筑边缘的长条凹槽，里面一个箭头标流向；管道口两端做成圆角；
    /// 接上线后槽外沿一条线色短条
    private func drawPortSlot(port: BuildingPort, cell: GridPoint, facing: BuildingRotation,
                              connected: Bool, context: inout GraphicsContext) {
        let center = cellCenter(cell)
        let out = facing.outputOffset
        let dx = CGFloat(out.col), dy = CGFloat(out.row)
        let length = cellSize * 0.7
        let depth = cellSize * 0.24
        let isVertical = facing == .left || facing == .right
        let slotW = isVertical ? depth : length
        let slotH = isVertical ? length : depth
        // 槽外沿贴着机身边框内侧
        let inset = cellSize * 0.5 - max(2, cellSize * 0.06) - depth / 2
        let c = CGPoint(x: center.x + dx * inset, y: center.y + dy * inset)
        let rect = CGRect(x: c.x - slotW / 2, y: c.y - slotH / 2, width: slotW, height: slotH)
        let corner = port.kind == .pipe ? depth / 2 : max(1, depth * 0.12)
        let slot = Path(roundedRect: rect, cornerRadius: corner)
        context.fill(slot, with: .color(FactoryCanvasPalette.portSlot))
        context.stroke(slot, with: .color(FactoryCanvasPalette.structure), lineWidth: max(0.6, cellSize * 0.012))

        // 箭头：出口朝外，入口朝里
        let sign: CGFloat = port.ioDirection == .output ? 1 : -1
        let a = max(2, depth * 0.22)
        let tip = CGPoint(x: c.x + dx * sign * a * 0.5, y: c.y + dy * sign * a * 0.5)
        var chevron = Path()
        chevron.move(to: CGPoint(x: tip.x - dx * sign * a - dy * a, y: tip.y - dy * sign * a + dx * a))
        chevron.addLine(to: tip)
        chevron.addLine(to: CGPoint(x: tip.x - dx * sign * a + dy * a, y: tip.y - dy * sign * a - dx * a))
        context.stroke(chevron, with: .color(connected ? FactoryCanvasPalette.ink : FactoryCanvasPalette.secondaryInk),
                       style: StrokeStyle(lineWidth: max(1, depth * 0.12), lineCap: .round, lineJoin: .round))

        if connected {
            let stripe = max(1, depth * 0.14)
            let along = length * 0.5
            let sc = CGPoint(x: c.x + dx * (depth / 2 - stripe / 2), y: c.y + dy * (depth / 2 - stripe / 2))
            let w = isVertical ? stripe : along, h = isVertical ? along : stripe
            context.fill(Path(CGRect(x: sc.x - w / 2, y: sc.y - h / 2, width: w, height: h)),
                         with: .color(port.kind == .pipe ? pipeColor : beltColor))
        }
    }

    // MARK: - 供电范围：选中供电桩、或正在放/拖供电桩时，把所有供电桩的范围（本体向四周扩 powerRange 格）画出来
    private var showsPowerRanges: Bool {
        if vm.selectedDefinition?.powerRange != nil { return true }
        if draggingDef?.powerRange != nil { return true }
        if case .place(let def) = vm.editMode, def.powerRange != nil { return true }
        return false
    }

    @ViewBuilder
    private var powerRangeLayer: some View {
        if showsPowerRanges {
            Canvas { context, _ in
                func rangeRect(_ placed: PlacedBuilding, _ def: BuildingDefinition, _ range: Int) -> CGRect {
                    let size = placed.effectiveSize(definition: def)
                    return CGRect(x: CGFloat(placed.origin.col - range) * cellSize,
                                  y: CGFloat(placed.origin.row - range) * cellSize,
                                  width: CGFloat(size.width + range * 2) * cellSize,
                                  height: CGFloat(size.height + range * 2) * cellSize)
                }
                let color = BuildingCategory.power.color
                for placed in vm.layout.buildings {
                    guard let def = BuildingDefinition.find(placed.definitionID), let range = def.powerRange else { continue }
                    let rect = rangeRect(placed, def, range)
                    let selected = placed.id == vm.selectedBuildingID
                    context.fill(Path(rect), with: .color(color.opacity(selected ? 0.16 : 0.07)))
                    context.stroke(Path(rect), with: .color(color.opacity(selected ? 0.8 : 0.35)),
                                   style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
                if let def = draggingDef, let range = def.powerRange, let loc = dropPreviewLocal {
                    let dummy = PlacedBuilding(definitionID: def.id, origin: cellAt(point: loc), rotation: vm.pendingRotation)
                    let rect = rangeRect(dummy, def, range)
                    context.fill(Path(rect), with: .color(color.opacity(0.12)))
                    context.stroke(Path(rect), with: .color(color.opacity(0.8)), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
            .allowsHitTesting(false)
        }
    }

    // MARK: - 拖拽放置预览（从建筑板拖入）
    @ViewBuilder
    private var dragPreview: some View {
        if let def = draggingDef, let loc = dropPreviewLocal {
            let cell = cellAt(point: loc)
            let canPlace = vm.canPlaceAt(def, cell: cell)
            let dummy = PlacedBuilding(definitionID: def.id, origin: cell, rotation: vm.pendingRotation)
            let size = dummy.effectiveSize(definition: def)
            let w = CGFloat(size.width) * cellSize
            let h = CGFloat(size.height) * cellSize
            let x = CGFloat(cell.col) * cellSize
            let y = CGFloat(cell.row) * cellSize

            ZStack {
                Rectangle().fill(canPlace ? def.category.color.opacity(0.3) : Color.red.opacity(0.25))
                Rectangle().stroke(canPlace ? def.category.color : Color.red,
                                   style: StrokeStyle(lineWidth: 2, dash: [6, 3]))
                VStack(spacing: 2) {
                    Image(systemName: def.category.icon)
                        .font(.system(size: min(w, h) * 0.28))
                        .foregroundColor(canPlace ? def.category.color : .red)
                    Text(vm.pendingRotation.symbol)
                        .font(.system(size: min(w, h) * 0.2))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .frame(width: w, height: h)
            .offset(x: x, y: y)
            .allowsHitTesting(false)
        }
    }

    // MARK: - 已放置建筑拖拽重定位
    // 只在选中模式、且有选中建筑时才铺这一小块透明手势层，精确盖在建筑当前渲染的矩形上——
    // 拖拽中建筑本体还画在原位，另外单独画一个跟手的预览框（绿色=能放，红色=不能放），
    // 松手时预览框在哪就试着挪到哪，不合法就地不动
    @ViewBuilder
    private var repositionHandle: some View {
        if vm.editMode == .select, let placed = vm.selectedPlaced, let def = vm.selectedDefinition {
            let size = placed.effectiveSize(definition: def)
            let w = CGFloat(size.width) * cellSize
            let h = CGFloat(size.height) * cellSize
            let x = CGFloat(placed.origin.col) * cellSize
            let y = CGFloat(placed.origin.row) * cellSize

            Color.clear
                .contentShape(Rectangle())
                .frame(width: w, height: h)
                .offset(x: x, y: y)
                .gesture(
                    DragGesture(minimumDistance: 6)
                        .onChanged { value in
                            if repositionOriginalOrigin == nil {
                                repositionOriginalOrigin = placed.origin
                            }
                            guard let origin = repositionOriginalOrigin else { return }
                            let dCol = Int((value.translation.width / cellSize).rounded())
                            let dRow = Int((value.translation.height / cellSize).rounded())
                            repositionCandidateOrigin = GridPoint(col: origin.col + dCol, row: origin.row + dRow)
                        }
                        .onEnded { _ in
                            if let candidate = repositionCandidateOrigin {
                                vm.commitReposition(placed.id, to: candidate)
                            }
                            repositionOriginalOrigin = nil
                            repositionCandidateOrigin = nil
                        }
                )

            if let candidate = repositionCandidateOrigin, candidate != placed.origin {
                let canPlace = vm.canReposition(placed.id, to: candidate)
                let color = canPlace ? def.category.color : Color.red
                ZStack {
                    Rectangle().fill(color.opacity(0.35))
                    Rectangle().stroke(color, style: StrokeStyle(lineWidth: 2, dash: [6, 3]))
                }
                .frame(width: w, height: h)
                .offset(x: CGFloat(candidate.col) * cellSize, y: CGFloat(candidate.row) * cellSize)
                .allowsHitTesting(false)
            }
        }
    }

    // MARK: - 框选：拉框的虚线框 + 拖整组时跟手的预览（绿 = 能放，红 = 出界或压到组外建筑）
    @ViewBuilder
    private var boxSelectionOverlay: some View {
        if vm.editMode == .boxSelect {
            if let a = boxDragStart, let b = boxDragCurrent, boxDragKind == .box {
                let minC = min(a.col, b.col), minR = min(a.row, b.row)
                let w = CGFloat(abs(a.col - b.col) + 1) * cellSize
                let h = CGFloat(abs(a.row - b.row) + 1) * cellSize
                ZStack {
                    Rectangle().fill(groupColor.opacity(0.10))
                    Rectangle().stroke(groupColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                }
                .frame(width: w, height: h)
                .offset(x: CGFloat(minC) * cellSize, y: CGFloat(minR) * cellSize)
                .allowsHitTesting(false)
            }
            if let delta = groupDragDelta, delta != GridPoint(col: 0, row: 0) {
                let ok = vm.canMoveGroup(by: delta)
                let color = ok ? Color(red: 0.4, green: 0.9, blue: 0.4) : Color.red
                let moving = vm.beltsMovingWithGroup()
                Canvas { context, _ in
                    let style = StrokeStyle(lineWidth: max(2, cellSize * 0.3), lineCap: .round, lineJoin: .round,
                                            dash: [cellSize * 0.5, cellSize * 0.25])
                    for belt in vm.layout.beltNetwork.belts where moving.contains(belt.id) {
                        var shifted = belt.segments
                        for i in shifted.indices { shifted[i].cell = shifted[i].cell + delta }
                        drawChain(shifted, color: color.opacity(0.8), blockedColor: color.opacity(0.8),
                                  blockedSet: [], style: style, radius: cellSize * 0.38, context: &context)
                    }
                }
                .allowsHitTesting(false)
                ForEach(vm.groupBuildings) { placed in
                    if let def = BuildingDefinition.find(placed.definitionID) {
                        let size = placed.effectiveSize(definition: def)
                        ZStack {
                            Rectangle().fill(color.opacity(0.3))
                            Rectangle().stroke(color, style: StrokeStyle(lineWidth: 2, dash: [6, 3]))
                        }
                        .frame(width: CGFloat(size.width) * cellSize, height: CGFloat(size.height) * cellSize)
                        .offset(x: CGFloat(placed.origin.col + delta.col) * cellSize,
                                y: CGFloat(placed.origin.row + delta.row) * cellSize)
                        .allowsHitTesting(false)
                    }
                }
            }
        }
    }

    // MARK: - 布局虚影：按住虚影拖动（拖到画面边缘自动滚动），点空白处虚影挪过去；绿 = 能放，红 = 压到建筑或出界
    @ViewBuilder
    private var placementOverlay: some View {
        if let placement = vm.pendingPlacement {
            let ok = vm.placementBlockedReason == nil
            let tint = ok ? Color(red: 0.4, green: 0.9, blue: 0.4) : Color.red
            let conflicts: Set<Int> = placement.saved.mapType == vm.layout.mapType ? [] : Set(placementConflictIndices(placement))
            Canvas { context, _ in
                let style = StrokeStyle(lineWidth: max(2, cellSize * 0.3), lineCap: .round, lineJoin: .round,
                                        dash: [cellSize * 0.5, cellSize * 0.25])
                for belt in placement.belts {
                    let color = belt.lineType == .belt ? beltColor : pipeColor
                    drawChain(belt.segments, color: color.opacity(0.75), blockedColor: color.opacity(0.75),
                              blockedSet: [], style: style, radius: cellSize * 0.38, context: &context)
                }
            }
            .allowsHitTesting(false)
            ForEach(Array(placement.buildings.enumerated()), id: \.offset) { index, placed in
                if let def = BuildingDefinition.find(placed.definitionID) {
                    let size = placed.effectiveSize(definition: def)
                    let w = CGFloat(size.width) * cellSize, h = CGFloat(size.height) * cellSize
                    ZStack {
                        Rectangle().fill(def.category.color.opacity(0.3))
                        Rectangle().stroke(conflicts.contains(index) ? Color(red: 0.95, green: 0.25, blue: 0.2) : def.category.color,
                                           style: StrokeStyle(lineWidth: 2, dash: [6, 3]))
                        Text(verbatim: def.displayName).minimumScaleFactor(0.35)
                            .font(.system(size: min(w, h) * 0.16, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.85)).lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .padding(2)
                    }
                    .frame(width: w, height: h)
                    .offset(x: CGFloat(placed.origin.col) * cellSize, y: CGFloat(placed.origin.row) * cellSize)
                    .allowsHitTesting(false)
                }
            }
            // 外框：颜色表示能不能放，同时也是拖动的把手
            let frameW = CGFloat(placement.size.width) * cellSize
            let frameH = CGFloat(placement.size.height) * cellSize
            Rectangle()
                .fill(tint.opacity(0.08))
                .overlay(Rectangle().stroke(tint, style: StrokeStyle(lineWidth: 2.5, dash: [8, 4])))
                .contentShape(Rectangle())
                .frame(width: frameW, height: frameH)
                .offset(x: CGFloat(placement.origin.col) * cellSize, y: CGFloat(placement.origin.row) * cellSize)
                .gesture(
                    DragGesture(minimumDistance: 2, coordinateSpace: .global)
                        .onChanged { v in
                            if placementDragStartOrigin == nil {
                                placementDragStartOrigin = vm.pendingPlacement?.origin
                                placementDragStartLocal = toLocal(v.startLocation)
                            }
                            boxDragFingerGlobal = v.location
                            autoScrollFinger = v.location
                            updatePlacementDrag()
                        }
                        .onEnded { _ in
                            autoScrollFinger = nil
                            placementDragStartOrigin = nil
                            placementDragStartLocal = nil
                            boxDragFingerGlobal = nil
                        }
                )
        }
    }

    /// 跨地图放置时哪些建筑会冲突（下标对应 placement.buildings），虚影上先标红框
    private func placementConflictIndices(_ placement: PendingPlacement) -> [Int] {
        let rules = vm.layout.mapType.rules
        return placement.buildings.enumerated().compactMap { index, placed in
            guard let def = BuildingDefinition.find(placed.definitionID) else { return nil }
            if !rules.allows(def) { return index }
            let ids = placed.selectedRecipeIDs.union(placed.selectedRecipeID.map { [$0] } ?? [])
            let blocked = vm.availableRecipes(for: def).contains { ids.contains($0.id) && rules.blockedMode(of: $0, on: def) != nil }
            if blocked || BuildingDefinition.warehousePortIDs.contains(def.id) { return index }
            return nil
        }
    }

    private func updatePlacementDrag() {
        guard let startOrigin = placementDragStartOrigin, let startLocal = placementDragStartLocal,
              let finger = boxDragFingerGlobal else { return }
        let local = toLocal(finger)
        vm.movePlacement(to: GridPoint(col: startOrigin.col + Int(((local.x - startLocal.x) / cellSize).rounded()),
                                       row: startOrigin.row + Int(((local.y - startLocal.y) / cellSize).rounded())))
    }

    // MARK: - 传送带起点标记
    @ViewBuilder
    private var beltStartMarker: some View {
        if let start = vm.beltStart {
            let x = CGFloat(start.col) * cellSize + cellSize / 2
            let y = CGFloat(start.row) * cellSize + cellSize / 2
            Circle()
                .stroke(Color(red: 0.4, green: 0.7, blue: 0.9), lineWidth: 2.5)
                .frame(width: cellSize * 0.6, height: cellSize * 0.6)
                .offset(x: x - cellSize * 0.3, y: y - cellSize * 0.3)
                .allowsHitTesting(false)
        }
    }

    // MARK: - 端口吸附高亮
    // 绿色 = 类型匹配且空闲，可以吸附；红色 = 类型不匹配或端口已被占用，拒绝吸附
    @ViewBuilder
    private var portSnapHighlight: some View {
        if let snap = vm.activeSnap {
            let isValid = snap.isKindMatch && !snap.isOccupied
            let color: Color = isValid ? Color(red: 0.4, green: 0.9, blue: 0.4) : Color.red
            let x = CGFloat(snap.externalCell.col) * cellSize
            let y = CGFloat(snap.externalCell.row) * cellSize
            ZStack {
                Rectangle().fill(color.opacity(0.3))
                Rectangle().stroke(color, lineWidth: 3)
            }
            .frame(width: cellSize, height: cellSize)
            .offset(x: x, y: y)
            .allowsHitTesting(false)
        }
    }

    // MARK: - 手势覆盖层
    // belt 模式：整个覆盖层激活，拦截拖拽
    // select/erase：只用 onTapGesture，完全不干扰 ScrollView 单指滚动
    // place：不响应
    @ViewBuilder
    private var gestureOverlay: some View {
        GeometryReader { geo in
            if vm.editMode == .boxSelect {
                // 框选：单指拖动在空地上是拉框，按在选中的建筑上是拖整组；轻点是加入/移出单个建筑
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        // 用全局坐标：画布自动滚动时靠 gridGlobalFrame 的变化重新换算手指所在格
                        DragGesture(minimumDistance: 4, coordinateSpace: .global)
                            .onChanged { v in
                                if boxDragKind == nil {
                                    let startLocal = toLocal(v.startLocation)
                                    let startCell = cellAt(point: startLocal)
                                    boxDragKind = isGroupMember(at: startCell) ? .group : .box
                                    boxDragStart = startCell
                                    boxDragStartLocal = startLocal
                                }
                                boxDragFingerGlobal = v.location
                                autoScrollFinger = v.location
                                updateBoxDrag()
                            }
                            .onEnded { _ in
                                autoScrollFinger = nil
                                switch boxDragKind {
                                case .group:
                                    if let delta = groupDragDelta { vm.moveGroup(by: delta) }
                                case .box:
                                    if let a = boxDragStart, let b = boxDragCurrent { vm.boxSelect(from: a, to: b) }
                                case nil:
                                    break
                                }
                                boxDragKind = nil
                                boxDragStart = nil
                                boxDragCurrent = nil
                                groupDragDelta = nil
                                boxDragStartLocal = nil
                                boxDragFingerGlobal = nil
                            }
                    )
                    .simultaneousGesture(
                        SpatialTapGesture().onEnded { tap in
                            vm.handleTap(at: cellAt(point: tap.location), slop: tapSlop)
                        }
                    )
            } else if vm.editMode == .belt || vm.editMode == .pipe || vm.editMode == .erase {
                // 画线 / 删除：拦截单指拖拽（画线跟着手指走、删除按住划过去连删），
                // 轻点（不拖）照样算点击；双指捏合由父层 simultaneousGesture 处理
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 2)
                            .onChanged { v in
                                let cell = cellAt(point: v.location)
                                if vm.editMode == .erase {
                                    if !eraseDragActive {
                                        eraseDragActive = true
                                        vm.beginUndoGroup()
                                    }
                                    if cell != lastErasedCell {
                                        lastErasedCell = cell
                                        vm.eraseAt(cell: cell)
                                    }
                                    return
                                }
                                // 传入相对于起点的像素偏移，跳格时决定先走哪个轴
                                let startCell = vm.beltStart ?? cell
                                let startCenter = cellCenter(startCell)
                                let offset = CGPoint(
                                    x: v.location.x - startCenter.x,
                                    y: v.location.y - startCenter.y
                                )
                                vm.handleBeltDragChanged(at: cell, point: offset)
                            }
                            .onEnded { v in
                                if eraseDragActive {
                                    eraseDragActive = false
                                    lastErasedCell = nil
                                    vm.endUndoGroup()
                                } else {
                                    vm.handleBeltDragEnded(at: cellAt(point: v.location))
                                }
                            }
                    )
                    .simultaneousGesture(
                        SpatialTapGesture().onEnded { tap in
                            vm.handleTap(at: cellAt(point: tap.location), slop: tapSlop)
                        }
                    )
            } else {
                // 非 belt：只用 onTapGesture，不干扰 ScrollView 单指滚动
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        vm.handleTap(at: cellAt(point: location), slop: tapSlop)
                    }
                    .onChange(of: dragLocationInGrid) { globalPt in
                        guard let globalPt, draggingDef != nil else {
                            vm.pendingDropCell = nil
                            dropPreviewLocal = nil
                            return
                        }
                        let origin = geo.frame(in: .global).origin
                        let local = CGPoint(x: globalPt.x - origin.x, y: globalPt.y - origin.y)
                        let gridW = CGFloat(cols) * cellSize
                        let gridH = CGFloat(rows) * cellSize
                        if local.x >= 0, local.y >= 0, local.x <= gridW, local.y <= gridH {
                            let cell = cellAt(point: local)
                            vm.pendingDropCell = cell
                            dropPreviewLocal = local
                            // 仓库取货口/存货口这类要贴边的建筑，靠拖拽落点自动转成对应朝向，不用手动转
                            if let def = draggingDef,
                               let suggested = vm.autoOrientedRotation(for: def, at: cell) {
                                vm.pendingRotation = suggested
                            }
                        } else {
                            dropPreviewLocal = nil
                        }
                    }
            }
        }
        .frame(width: CGFloat(cols) * cellSize, height: CGFloat(rows) * cellSize)
    }

    // MARK: - 辅助
    private func toLocal(_ global: CGPoint) -> CGPoint {
        CGPoint(x: global.x - gridGlobalFrame.minX, y: global.y - gridGlobalFrame.minY)
    }

    /// 按下的那格是不是选中的建筑或选中的线（是就拖整组，不是就拉框）
    private func isGroupMember(at cell: GridPoint) -> Bool {
        if let hit = vm.building(at: cell) { return vm.groupSelection.contains(hit.placed.id) }
        return vm.layout.beltNetwork.beltIDs(at: cell).contains { vm.groupBeltSelection.contains($0) }
    }

    /// 按手指当前位置更新框或整组位移（手指移动、画布自动滚动都会调）
    private func updateBoxDrag() {
        guard let finger = boxDragFingerGlobal else { return }
        let local = toLocal(finger)
        switch boxDragKind {
        case .group:
            guard let start = boxDragStartLocal else { return }
            groupDragDelta = GridPoint(col: Int(((local.x - start.x) / cellSize).rounded()),
                                       row: Int(((local.y - start.y) / cellSize).rounded()))
        case .box:
            boxDragCurrent = cellAt(point: local)
        case nil:
            break
        }
    }

    /// 格子缩到比 44pt 小时，点击额外往外找几格，保证手指的可点范围
    private var tapSlop: Int {
        cellSize >= 44 ? 0 : Int(ceil((44 - cellSize) / 2 / cellSize))
    }

    func cellAt(point: CGPoint) -> GridPoint {
        GridPoint(
            col: max(0, min(cols - 1, Int(point.x / cellSize))),
            row: max(0, min(rows - 1, Int(point.y / cellSize)))
        )
    }

    private func cellCenter(_ cell: GridPoint) -> CGPoint {
        CGPoint(x: CGFloat(cell.col) * cellSize + cellSize / 2,
                y: CGFloat(cell.row) * cellSize + cellSize / 2)
    }

}

private final class GridFrameBox {
    var frame: CGRect = .zero
}

/// 端口外接格 → 线在这一格该怎么走：出口外接格里线是从口里出来的（沿出口朝向），
/// 入口外接格里线是要钻进口里的（朝向的反方向）。key 是 "列,行,item/pipe"。
/// 两台机器面对面只隔一格时，同一格会是两个口的外接格，所以每格存所有候选方向，画的时候再挑
private final class PortEndDirections {
    var headDir: [String: [GridPoint]] = [:]
    var tailDir: [String: [GridPoint]] = [:]
}
