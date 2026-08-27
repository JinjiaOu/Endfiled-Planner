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

    @State private var beltAnimPhase: CGFloat = 0

    private var cols: Int { FactoryGridModel.gridCols }
    private var rows: Int { FactoryGridModel.gridRows }

    var body: some View {
        ZStack(alignment: .topLeading) {
            gridLines
            beltsLayer
            buildingsLayer
            dragPreview
            beltStartMarker
            portSnapHighlight
            gestureOverlay
        }
        .frame(width: CGFloat(cols) * cellSize, height: CGFloat(rows) * cellSize)
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                beltAnimPhase = 20
            }
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
                with: .color(Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.08)),
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
                with: .color(Color(red: 1.0, green: 0.8, blue: 0.0).opacity(0.15)),
                lineWidth: 1)
        }
        .frame(width: CGFloat(cols) * cellSize, height: CGFloat(rows) * cellSize)
    }

    // 橙色传送带主色 / 蓝色管道主色
    private let beltColor      = Color(red: 1.0, green: 0.55, blue: 0.1)
    private let pipeColor      = Color(red: 0.3, green: 0.7, blue: 1.0)
    private let beltBlockedColor = Color.red
    private let beltArrowColor = Color.white     // 方向箭头用白色，对比度高

    /// 同一格、同一轴上如果传送带和管道都经过（平行走线），左右/上下分显，各占半格宽度
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
            let occupied = vm.occupiedBuildingCellKeys()
            let allSegs = vm.layout.beltNetwork.allSegments
            let sharedKeys = sharedAxisKeys(allSegs + vm.beltPreviewSegments)

            // 每条带独立画（保证 chain 分析正确，衔接带圆角，穿插带不混）
            for belt in vm.layout.beltNetwork.belts {
                let blockedSet = Set(belt.segments
                    .filter { occupied.contains("\($0.cell.col),\($0.cell.row)") }
                    .map { "\($0.cell.col),\($0.cell.row)" })
                drawBeltPath(segments: belt.segments,
                             lineType: belt.lineType,
                             sharedKeys: sharedKeys,
                             blockedSet: blockedSet,
                             isPreview: false, context: &context)
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

    private func canonicalPerp(for axis: BeltAxis) -> GridPoint {
        axis == .horizontal ? GridPoint(col: 0, row: 1) : GridPoint(col: 1, row: 0)
    }

    private func axisOf(_ dir: GridPoint) -> BeltAxis {
        dir.col != 0 ? .horizontal : .vertical
    }

    /// 传送带/管道渲染：Belt.segments 本身已有序，直接画圆角折线，不需要重新串链
    private func drawBeltPath(segments: [BeltSegment],
                              lineType: LineType,
                              sharedKeys: Set<String>,
                              blockedSet: Set<String>,
                              isPreview: Bool,
                              context: inout GraphicsContext) {
        guard !segments.isEmpty else { return }

        // 整条带只要有任意一格和另一类型共占同一格同一轴，就整条按半宽偏移绘制，
        // 避免遮挡（相邻两格局部共存、局部不共存的情况很少见，不做逐格变宽度处理）
        let isShared = segments.contains {
            sharedKeys.contains("\($0.cell.col),\($0.cell.row),\($0.axis.rawValue)")
        }
        let widthScale: CGFloat = isShared ? 0.5 : 1.0
        let offsetSign: CGFloat = lineType == .belt ? -1 : 1
        let shift = isShared ? cellSize * 0.25 * offsetSign : 0

        let baseColor = lineType == .belt ? beltColor : pipeColor

        // 线宽 = 格子宽度（填满格子），共存时减半
        let lineW  = cellSize * widthScale
        let radius = cellSize * 0.38 * widthScale
        let alpha: Double = isPreview ? 0.45 : 1.0
        let dashPattern: [CGFloat] = isPreview ? [cellSize * 0.7, cellSize * 0.3] : []

        // 背景层：暗色
        let bgStyle = StrokeStyle(lineWidth: lineW, lineCap: .butt, lineJoin: .miter)
        drawChain(segments, color: baseColor.opacity(alpha * 0.55),
                  blockedColor: beltBlockedColor.opacity(alpha * 0.55),
                  blockedSet: blockedSet, style: bgStyle, radius: radius,
                  shift: shift, context: &context)

        // 前景层：稍窄亮色
        let fgStyle = StrokeStyle(lineWidth: lineW * 0.55, lineCap: .butt, lineJoin: .miter,
                                  dash: dashPattern,
                                  dashPhase: isPreview ? 0 : beltAnimPhase * cellSize * 0.05)
        drawChain(segments, color: baseColor.opacity(alpha),
                  blockedColor: beltBlockedColor.opacity(alpha),
                  blockedSet: blockedSet, style: fgStyle, radius: radius,
                  shift: shift, context: &context)

        // 方向箭头：每格中央画白色实心三角，明显
        for seg in segments {
            var c = cellCenter(seg.cell)
            let cellKey = "\(seg.cell.col),\(seg.cell.row)"
            let segShared = sharedKeys.contains("\(seg.cell.col),\(seg.cell.row),\(seg.axis.rawValue)")
            if segShared {
                let perp = canonicalPerp(for: seg.axis)
                let s = cellSize * 0.25 * offsetSign
                c = CGPoint(x: c.x + CGFloat(perp.col) * s, y: c.y + CGFloat(perp.row) * s)
            }
            let isBlocked = blockedSet.contains(cellKey)
            // 箭头大小约为格子的 30%，共存时缩小到半宽的箭头
            let arrowSize = cellSize * 0.30 * (segShared ? 0.6 : 1.0)
            drawArrow(at: c, dir: seg.toDir, size: arrowSize,
                      color: isBlocked ? Color.white.opacity(0.5) : Color.white.opacity(alpha * 0.9),
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
    /// - 线宽 = 格子宽，端点对齐格子边缘（占满整格）
    /// - 拐角处用 quadCurve 做圆弧
    private func drawChain(_ chain: [BeltSegment],
                           color: Color,
                           blockedColor: Color,
                           blockedSet: Set<String>,
                           style: StrokeStyle,
                           radius: CGFloat,
                           shift: CGFloat,
                           context: inout GraphicsContext) {
        guard !chain.isEmpty else { return }

        // 共存时垂直于每一段自身走向的偏移量（正交方向已经用 canonicalPerp 固定，
        // 保证同一类型不管朝哪个方向走都稳定偏到同一侧，不会因为流动方向不同而两条线叠在一起）
        func offset(for dir: GridPoint) -> CGPoint {
            guard shift != 0 else { return .zero }
            let perp = canonicalPerp(for: axisOf(dir))
            return CGPoint(x: CGFloat(perp.col) * shift, y: CGFloat(perp.row) * shift)
        }

        // 合并同格拐角段为关键点
        struct KP { var center: CGPoint; var inDir: GridPoint; var outDir: GridPoint; var blocked: Bool }
        var kps: [KP] = []
        var i = 0
        while i < chain.count {
            let seg = chain[i]
            let c = cellCenter(seg.cell)
            let key = "\(seg.cell.col),\(seg.cell.row)"
            let blocked = blockedSet.contains(key)
            if i + 1 < chain.count && chain[i + 1].cell == seg.cell {
                kps.append(KP(center: c, inDir: seg.fromDir, outDir: chain[i+1].toDir, blocked: blocked))
                i += 2
            } else {
                kps.append(KP(center: c, inDir: seg.fromDir, outDir: seg.toDir, blocked: blocked))
                i += 1
            }
        }
        guard !kps.isEmpty else { return }

        // butt cap 不延伸，所以端点必须设在格子实际边缘。
        // 起点 = 起始格入口边缘（格子外边缘，中心向入口方向偏移半格）
        // 终点 = 终止格出口边缘（格子外边缘，中心向出口方向偏移半格）
        // 中间各格：只保留真正拐角格的中心点作为折点，直线段不需要中间点
        let first = kps[0]; let last = kps[kps.count - 1]
        var pts: [CGPoint] = []
        let startOffset = offset(for: first.inDir)
        pts.append(CGPoint(
            x: first.center.x - CGFloat(first.inDir.col) * cellSize * 0.5 + startOffset.x,
            y: first.center.y - CGFloat(first.inDir.row) * cellSize * 0.5 + startOffset.y))
        // 只加拐角格的中心（直线段的中间格不需要，连起来就是直线）
        for idx in 0..<kps.count {
            let kp = kps[idx]
            let isFirst = idx == 0
            let isLast  = idx == kps.count - 1
            let prevDir = isFirst ? kp.inDir  : kps[idx - 1].outDir
            let nextDir = isLast  ? kp.outDir : kps[idx + 1].inDir
            // 方向变了才是拐角，需要保留中心点（偏移用出方向所在的轴，和相邻直线段衔接一致）
            let turning = (prevDir.col != nextDir.col) || (prevDir.row != nextDir.row)
            if turning {
                let o = offset(for: kp.outDir)
                pts.append(CGPoint(x: kp.center.x + o.x, y: kp.center.y + o.y))
            }
        }
        let endOffset = offset(for: last.outDir)
        pts.append(CGPoint(
            x: last.center.x + CGFloat(last.outDir.col) * cellSize * 0.5 + endOffset.x,
            y: last.center.y + CGFloat(last.outDir.row) * cellSize * 0.5 + endOffset.y))

        // 构建圆角路径
        var path = Path()
        path.move(to: pts[0])
        for j in 1..<pts.count - 1 {
            let prev = pts[j-1]; let curr = pts[j]; let next = pts[j+1]
            let d1 = CGPoint(x: curr.x - prev.x, y: curr.y - prev.y)
            let d2 = CGPoint(x: next.x - curr.x, y: next.y - curr.y)
            let isCorner = (abs(d1.x) > 0.1) != (abs(d2.x) > 0.1)
            if isCorner {
                let lenIn = dist(prev, curr); let lenOut = dist(curr, next)
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

        // 如果有阻碍格则用阻碍色，否则正常色
        let hasBlocked = kps.contains { $0.blocked }
        context.stroke(path, with: .color(hasBlocked ? blockedColor : color), style: style)
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

        return ZStack {
            Rectangle().fill(def.category.color.opacity(isSelected ? 0.4 : 0.25))
            Rectangle().stroke(
                isSelected ? Color(red: 1.0, green: 0.8, blue: 0.0) : def.category.color.opacity(0.6),
                lineWidth: isSelected ? 2.5 : 1.5)
            VStack(spacing: 3) {
                Image(systemName: def.category.icon)
                    .font(.system(size: min(w, h) * 0.28))
                    .foregroundColor(def.category.color)
                Text(def.name)
                    .font(.system(size: min(w, h) * 0.16, weight: .bold, design: .monospaced))
                    .foregroundColor(.white).lineLimit(1)
                Text(placed.rotation.symbol)
                    .font(.system(size: min(w, h) * 0.18))
                    .foregroundColor(.white.opacity(0.5))
            }.padding(4)
            if isSelected {
                VStack {
                    HStack {
                        Spacer()
                        Circle().fill(Color(red: 1.0, green: 0.8, blue: 0.0))
                            .frame(width: 8, height: 8).padding(4)
                    }
                    Spacer()
                }
            }
        }
        .frame(width: w, height: h)
        .offset(x: x, y: y)
    }

    // MARK: - 拖拽放置预览（从建筑板拖入）
    @ViewBuilder
    private var dragPreview: some View {
        if let def = draggingDef, let loc = dragLocationInGrid {
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
            if vm.editMode == .belt || vm.editMode == .pipe {
                // Belt/Pipe 专用：拦截单指拖拽，双指捏合由父层 simultaneousGesture 处理
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 2)
                            .onChanged { v in
                                let cell = cellAt(point: v.location)
                                // 传入相对于起点的像素偏移，用于判断先走哪个轴
                                let startCell = vm.beltStart ?? cell
                                let startCenter = cellCenter(startCell)
                                let offset = CGPoint(
                                    x: v.location.x - startCenter.x,
                                    y: v.location.y - startCenter.y
                                )
                                vm.handleBeltDragChanged(at: cell, point: offset)
                            }
                            .onEnded { v in
                                vm.handleBeltDragEnded(at: cellAt(point: v.location))
                            }
                    )
            } else {
                // 非 belt：只用 onTapGesture，不干扰 ScrollView 单指滚动
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        switch vm.editMode {
                        case .select, .erase:
                            vm.handleTap(at: cellAt(point: location))
                        default:
                            break
                        }
                    }
                    .onChange(of: dragLocationInGrid) { globalPt in
                        guard let globalPt, draggingDef != nil else {
                            vm.pendingDropCell = nil
                            return
                        }
                        let origin = geo.frame(in: .global).origin
                        let local = CGPoint(x: globalPt.x - origin.x, y: globalPt.y - origin.y)
                        let gridW = CGFloat(cols) * cellSize
                        let gridH = CGFloat(rows) * cellSize
                        if local.x >= 0, local.y >= 0, local.x <= gridW, local.y <= gridH {
                            vm.pendingDropCell = cellAt(point: local)
                            dragLocationInGrid = local
                        }
                    }
            }
        }
        .frame(width: CGFloat(cols) * cellSize, height: CGFloat(rows) * cellSize)
    }

    // MARK: - 辅助
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
