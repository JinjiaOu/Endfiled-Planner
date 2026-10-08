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
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            gridFrameBox.frame = frame
            if boxDragKind != nil { updateBoxDrag() }
            if placementDragStartOrigin != nil { updatePlacementDrag() }
        }
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
    private let selectionColor = Color(red: 1.0, green: 0.8, blue: 0.0)
    private let beltColor      = Color(red: 1.0, green: 0.55, blue: 0.1)
    private let pipeColor      = Color(red: 0.3, green: 0.7, blue: 1.0)
    private let beltBlockedColor = Color.red
    private let beltArrowColor = Color.white     // 方向箭头用白色，对比度高

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
            // 物流桥/管道桥是特意留给线穿过去的交叉节点，不算挡路，排除在外，
            // 不然线一穿过自己触发生成的桥就会被判定成"撞到建筑"整条标红
            let occupied = vm.lineBlockingCellKeys()
            let allSegs = vm.layout.beltNetwork.allSegments
            let sharedKeys = sharedAxisKeys(allSegs + vm.beltPreviewSegments)

            // 传送带先画（打底），管道后画（叠在上面），保证共存时管道细线始终可见
            for belt in vm.layout.beltNetwork.belts where belt.lineType == .belt {
                drawOneBelt(belt, occupied: occupied, sharedKeys: sharedKeys, isPreview: false, context: &context)
            }
            for belt in vm.layout.beltNetwork.belts where belt.lineType == .pipe {
                drawOneBelt(belt, occupied: occupied, sharedKeys: sharedKeys, isPreview: false, context: &context)
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
                             isPreview: Bool, context: inout GraphicsContext) {
        let blockedSet = Set(belt.segments
            .filter { occupied.contains("\($0.cell.col),\($0.cell.row)") }
            .map { "\($0.cell.col),\($0.cell.row)" })
        drawBeltPath(segments: belt.segments, lineType: belt.lineType,
                     sharedKeys: sharedKeys, blockedSet: blockedSet,
                     isPreview: isPreview, context: &context)
    }

    /// 传送带/管道渲染：Belt.segments 本身已有序，直接画圆角折线，不需要重新串链
    private func drawBeltPath(segments: [BeltSegment],
                              lineType: LineType,
                              sharedKeys: Set<String>,
                              blockedSet: Set<String>,
                              isPreview: Bool,
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
        let alpha: Double = isPreview ? 0.45 : 1.0
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

        // 方向箭头：每格中央画白色实心三角，明显
        for seg in segments {
            let c = cellCenter(seg.cell)
            let cellKey = "\(seg.cell.col),\(seg.cell.row)"
            let isBlocked = blockedSet.contains(cellKey)
            // 箭头大小约为格子的 30%，管道缩细时箭头也跟着小一号但不要太小看不清
            let arrowSize = cellSize * 0.30 * max(widthScale, 0.55)
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
        pts.append(CGPoint(
            x: first.center.x - CGFloat(first.inDir.col) * cellSize * 0.5,
            y: first.center.y - CGFloat(first.inDir.row) * cellSize * 0.5))
        // 只加拐角格的中心（直线段的中间格不需要，连起来就是直线）
        for idx in 0..<kps.count {
            let kp = kps[idx]
            let isFirst = idx == 0
            let isLast  = idx == kps.count - 1
            let prevDir = isFirst ? kp.inDir  : kps[idx - 1].outDir
            let nextDir = isLast  ? kp.outDir : kps[idx + 1].inDir
            // 方向变了才是拐角，需要保留中心点
            let turning = (prevDir.col != nextDir.col) || (prevDir.row != nextDir.row)
            if turning { pts.append(kp.center) }
        }
        pts.append(CGPoint(
            x: last.center.x + CGFloat(last.outDir.col) * cellSize * 0.5,
            y: last.center.y + CGFloat(last.outDir.row) * cellSize * 0.5))

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
            settingLabel = ("地图不支持", false)
        } else if def.choosesOutletMaterial {
            let name = placed.outletMaterialID.flatMap(ItemCatalog.name(for:))
            settingLabel = (name ?? "未设置", name != nil)
        } else if def.id == "log_conditioner" || def.id == "log_pipe_conditioner",
                  let name = placed.filterItemID.flatMap(ItemCatalog.name(for:)) {
            settingLabel = (name, true)
        } else {
            settingLabel = nil
        }

        return ZStack {
            Rectangle().fill(def.category.color.opacity(isSelected ? 0.4 : 0.25))
            Rectangle().stroke(
                isSelected ? Color(red: 1.0, green: 0.8, blue: 0.0)
                    : hasMapConflict ? Color(red: 0.95, green: 0.25, blue: 0.2) : def.category.color.opacity(0.6),
                lineWidth: isSelected || hasMapConflict ? 2.5 : 1.5)
            if isThin {
                HStack(spacing: 4) {
                    Image(systemName: def.category.icon)
                        .font(.system(size: min(w, h) * 0.5))
                        .foregroundColor(def.category.color)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(def.name)
                            .font(.system(size: min(w, h) * 0.32, weight: .bold, design: .monospaced))
                            .foregroundColor(.white).lineLimit(1)
                        if let setting = settingLabel {
                            Text(setting.text)
                                .font(.system(size: min(w, h) * 0.26, design: .monospaced))
                                .foregroundColor(hasMapConflict ? Color(red: 0.95, green: 0.35, blue: 0.3)
                                                 : setting.isSet ? Color(red: 0.4, green: 0.8, blue: 0.2)
                                                 : .white.opacity(0.35))
                                .lineLimit(1)
                        }
                    }
                    Text(flowSymbol)
                        .font(.system(size: min(w, h) * 0.4))
                        .foregroundColor(.white.opacity(0.5))
                }
                .padding(4)
                .minimumScaleFactor(0.6)
            } else {
                VStack(spacing: 3) {
                    Image(systemName: def.category.icon)
                        .font(.system(size: min(w, h) * 0.28))
                        .foregroundColor(def.category.color)
                    Text(def.name)
                        .font(.system(size: min(w, h) * 0.16, weight: .bold, design: .monospaced))
                        .foregroundColor(.white).lineLimit(1)
                    if let setting = settingLabel {
                        Text(setting.text)
                            .font(.system(size: min(w, h) * 0.14, design: .monospaced))
                            .foregroundColor(hasMapConflict ? Color(red: 0.95, green: 0.35, blue: 0.3)
                                             : setting.isSet ? Color(red: 0.4, green: 0.8, blue: 0.2)
                                             : .white.opacity(0.35))
                            .lineLimit(1)
                    }
                    Text(flowSymbol)
                        .font(.system(size: min(w, h) * 0.18))
                        .foregroundColor(.white.opacity(0.5))
                }.padding(4)
            }
            if isSelected {
                // 选中框：整圈黄色粗边，缩小看全图时也一眼能找到
                Rectangle()
                    .stroke(Color(red: 1.0, green: 0.8, blue: 0.0), lineWidth: max(2, cellSize * 0.08))
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
        .overlay(alignment: .topTrailing) {
            if let displayedStatus {
                Circle()
                    .fill(statusColor(displayedStatus))
                    .overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 1))
                    .frame(width: 8, height: 8)
                    .padding(4)
                    .accessibilityLabel(displayedStatus.label)
                    .allowsHitTesting(false)
            }
        }
        .opacity(placed.isActive ? 1 : 0.45)
        .clipped()
        .offset(x: x, y: y)
    }

    private func statusColor(_ status: FlowSimulator.MachineStatus) -> Color {
        switch status {
        case .running: return .green
        case .blocked: return .red
        case .starved: return .orange
        case .inactive, .noRecipe: return .gray
        }
    }

    // MARK: - 端口标记层：每个入口/出口在建筑边缘画一个小圆点，接上线是实心，没接是空心
    private var portsLayer: some View {
        ForEach(vm.layout.buildings) { placed in
            if let def = BuildingDefinition.find(placed.definitionID) {
                ForEach(Array(def.ports.enumerated()), id: \.offset) { _, port in
                    portMarker(port: port, placed: placed, def: def)
                }
            }
        }
    }

    private func portMarker(port: BuildingPort, placed: PlacedBuilding, def: BuildingDefinition) -> some View {
        let (cell, facing) = port.resolvedPosition(placed: placed, definition: def)
        let center = cellCenter(cell)
        // 往端口朝外的方向偏一点，让点落在建筑边缘上而不是格子正中心
        let inset = cellSize * 0.34
        let cx = center.x + CGFloat(facing.outputOffset.col) * inset
        let cy = center.y + CGFloat(facing.outputOffset.row) * inset
        let connected = vm.isPortConnected(port, placed: placed, definition: def)
        let color = port.kind == .pipe ? pipeColor : beltColor
        let dot = cellSize * 0.22

        return ZStack {
            Circle().fill(connected ? color : Color(red: 0.06, green: 0.07, blue: 0.10))
            Circle().stroke(color, lineWidth: connected ? 0 : 1.5)
        }
        .frame(width: dot, height: dot)
        .offset(x: cx - dot / 2, y: cy - dot / 2)
        .allowsHitTesting(false)
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
                        Text(def.name)
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
