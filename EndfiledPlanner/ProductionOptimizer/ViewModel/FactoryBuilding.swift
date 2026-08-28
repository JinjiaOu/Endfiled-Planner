//
//  FactoryBuilding.swift
//  EndfiledPlanner
//
//  Created by Jinjia Ou on 4/3/26.
//

import SwiftUI

// MARK: - 建筑方向
enum BuildingRotation: Int, Codable, CaseIterable {
    case up = 0
    case right = 1
    case down = 2
    case left = 3

    var next: BuildingRotation {
        BuildingRotation(rawValue: (rawValue + 1) % 4) ?? .up
    }

    var opposite: BuildingRotation {
        BuildingRotation(rawValue: (rawValue + 2) % 4) ?? .up
    }

    var symbol: String {
        switch self {
        case .up:    return "↑"
        case .right: return "→"
        case .down:  return "↓"
        case .left:  return "←"
        }
    }

    /// 输出端口方向（相对于建筑朝向）
    var outputOffset: GridPoint {
        switch self {
        case .up:    return GridPoint(col: 0, row: -1)
        case .right: return GridPoint(col: 1,  row: 0)
        case .down:  return GridPoint(col: 0,  row: 1)
        case .left:  return GridPoint(col: -1, row: 0)
        }
    }
}

// MARK: - 建筑类别（对应游戏内分类，仅保留基建有用的）
enum BuildingCategory: String, Codable, CaseIterable {
    case logistics   = "物流设备"
    case extraction  = "资源开采"   // 仅水泵
    case storage     = "仓储存区"
    case production  = "基础生产"
    case synthesis   = "合成制造"
    case power       = "电力供应"

    var color: Color {
        switch self {
        case .logistics:  return Color(red: 0.4, green: 0.7, blue: 0.9)
        case .extraction: return Color(red: 0.7, green: 0.5, blue: 0.2)
        case .storage:    return Color(red: 0.6, green: 0.6, blue: 0.6)
        case .production: return Color(red: 0.9, green: 0.3, blue: 0.2)
        case .synthesis:  return Color(red: 0.6, green: 0.4, blue: 0.9)
        case .power:      return Color(red: 1.0, green: 0.8, blue: 0.0)
        }
    }

    var icon: String {
        switch self {
        case .logistics:  return "arrow.left.and.right"
        case .extraction: return "drop.fill"
        case .storage:    return "shippingbox.fill"
        case .production: return "flame.fill"
        case .synthesis:  return "gearshape.2.fill"
        case .power:      return "bolt.fill"
        }
    }
}

// MARK: - 地图
/// 仓库取线机制是地图特定的：四号谷地只能贴外围放，武陵要连取线终端，
/// 所以布局本身要记住自己是哪张地图，建筑清单也要按地图过滤
enum MapType: String, Codable, CaseIterable {
    case valley4 = "四号谷地"
    case wuling  = "武陵"

    var displayName: String { rawValue }
}

// MARK: - 端口类型
enum PortKind: String, Codable {
    case item   // 普通物流口
    case pipe   // 管道口
}

enum PortIODirection: String, Codable {
    case input
    case output
}

/// 建筑端口定义
/// - edge：这个口未旋转时所在的边（up/right/down/left），已经把"输入口的朝向其实是流入方向而非所在边"
///   这层换算做完了——parser 里是用旋转角反推出来的，这里存的已经是纯几何意义上的边
/// - indexOnEdge：口在这条边上的原始网格偏移量（不是序号！同一边内可能跳格，比如反应池的两个输入口在
///   x=1、x=3，不是 0、1），左→右 / 上→下递增，可以直接当偏移量用来算实际格子
struct BuildingPort: Codable, Hashable {
    let kind: PortKind
    let ioDirection: PortIODirection
    let edge: BuildingRotation
    let indexOnEdge: Int
}

// MARK: - 建筑定义（模板）
struct BuildingDefinition: Identifiable, Hashable {
    let id: String
    let name: String
    let category: BuildingCategory
    let size: GridSize          // 占格尺寸（未旋转）
    let powerUsage: Double      // 功率（MW）
    let ports: [BuildingPort]
    /// nil = 两张地图都能造；非 nil 就只有列出来的地图能造（比如取线终端只有武陵有）
    let allowedMaps: Set<MapType>?

    init(id: String, name: String, category: BuildingCategory, size: GridSize,
         powerUsage: Double, ports: [BuildingPort], allowedMaps: Set<MapType>? = nil) {
        self.id = id
        self.name = name
        self.category = category
        self.size = size
        self.powerUsage = powerUsage
        self.ports = ports
        self.allowedMaps = allowedMaps
    }

    func isAvailable(on map: MapType) -> Bool {
        allowedMaps?.contains(map) ?? true
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: BuildingDefinition, rhs: BuildingDefinition) -> Bool { lhs.id == rhs.id }
}

// MARK: - 端口坐标换算
extension BuildingRotation {
    /// 把建筑未旋转时局部坐标系里的一个点，按建筑当前旋转换算成旋转后局部坐标系里的点
    /// （旋转规则与 PlacedBuilding.effectiveSize 的宽高互换保持一致）
    static func rotate(_ point: GridPoint, in size: GridSize, by rotation: BuildingRotation) -> GridPoint {
        let w = size.width, h = size.height
        switch rotation {
        case .up:    return point
        case .right: return GridPoint(col: h - 1 - point.row, row: point.col)
        case .down:  return GridPoint(col: w - 1 - point.col, row: h - 1 - point.row)
        case .left:  return GridPoint(col: point.row, row: w - 1 - point.col)
        }
    }
}

extension BuildingPort {
    /// 未旋转时，这个端口在建筑局部坐标系里的格子偏移
    func localOffset(definitionSize size: GridSize) -> GridPoint {
        switch edge {
        case .up:    return GridPoint(col: indexOnEdge, row: 0)
        case .down:  return GridPoint(col: indexOnEdge, row: size.height - 1)
        case .left:  return GridPoint(col: 0, row: indexOnEdge)
        case .right: return GridPoint(col: size.width - 1, row: indexOnEdge)
        }
    }

    /// 给定建筑实例（origin + 当前旋转），换算出这个端口实际所在的网格坐标，以及旋转后的实际朝向
    /// （朝向 = 端口的物流流动方向：输出口是"往外流"的方向，输入口是"往里流"的方向）
    func resolvedPosition(placed: PlacedBuilding, definition: BuildingDefinition) -> (cell: GridPoint, facing: BuildingRotation) {
        let local = localOffset(definitionSize: definition.size)
        let rotatedLocal = BuildingRotation.rotate(local, in: definition.size, by: placed.rotation)
        let cell = GridPoint(col: placed.origin.col + rotatedLocal.col,
                              row: placed.origin.row + rotatedLocal.row)
        let facing = BuildingRotation(rawValue: (edge.rawValue + placed.rotation.rawValue) % 4) ?? .up
        return (cell, facing)
    }
}

// MARK: - 网格坐标
struct GridPoint: Codable, Hashable, Equatable {
    var col: Int
    var row: Int

    static func + (lhs: GridPoint, rhs: GridPoint) -> GridPoint {
        GridPoint(col: lhs.col + rhs.col, row: lhs.row + rhs.row)
    }
}

// MARK: - 网格尺寸
struct GridSize: Codable, Hashable {
    var width: Int
    var height: Int
}

// MARK: - 已放置的建筑实例
struct PlacedBuilding: Identifiable, Codable {
    let id: UUID
    let definitionID: String
    var origin: GridPoint       // 左上角坐标
    var rotation: BuildingRotation
    var isActive: Bool
    /// 这台机器有多个配方时，用户选的是哪一个（下标对应 RecipeViewModel.recipesByMachine() 里该机器的配方列表）
    var selectedRecipeIndex: Int? = nil
    /// 仅取线出口用：当前设置的取货材料，未设置时不产出
    var outletMaterial: String? = nil

    init(definitionID: String, origin: GridPoint, rotation: BuildingRotation = .up) {
        self.id = UUID()
        self.definitionID = definitionID
        self.origin = origin
        self.rotation = rotation
        self.isActive = true
    }

    /// 根据旋转计算实际占用尺寸
    func effectiveSize(definition: BuildingDefinition) -> GridSize {
        let s = definition.size
        switch rotation {
        case .up, .down:   return s
        case .left, .right: return GridSize(width: s.height, height: s.width)
        }
    }

    /// 占用的所有格子
    func occupiedCells(definition: BuildingDefinition) -> [GridPoint] {
        let s = effectiveSize(definition: definition)
        var cells: [GridPoint] = []
        for r in 0..<s.height {
            for c in 0..<s.width {
                cells.append(GridPoint(col: origin.col + c, row: origin.row + r))
            }
        }
        return cells
    }
}

// MARK: - 传送带方向
enum BeltAxis: String, Codable {
    case horizontal   // 水平段
    case vertical     // 垂直段
}

// MARK: - 线路类型：传送带 or 管道
enum LineType: String, Codable, CaseIterable {
    case belt   // 橙色，普通物流
    case pipe   // 蓝色，液体/气体

    var displayName: String {
        switch self {
        case .belt: return "传送带"
        case .pipe: return "管道"
        }
    }
}

// MARK: - 传送带段（单格）
struct BeltSegment: Identifiable, Codable, Hashable {
    let id: UUID
    var cell: GridPoint
    var axis: BeltAxis
    var fromDir: GridPoint
    var toDir: GridPoint
    var lineType: LineType

    init(cell: GridPoint, axis: BeltAxis, fromDir: GridPoint, toDir: GridPoint, lineType: LineType = .belt) {
        self.id = UUID()
        self.cell = cell
        self.axis = axis
        self.fromDir = fromDir
        self.toDir = toDir
        self.lineType = lineType
    }

    private enum CodingKeys: String, CodingKey {
        case id, cell, axis, fromDir, toDir, lineType
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        cell = try c.decode(GridPoint.self, forKey: .cell)
        axis = try c.decode(BeltAxis.self, forKey: .axis)
        fromDir = try c.decode(GridPoint.self, forKey: .fromDir)
        toDir = try c.decode(GridPoint.self, forKey: .toDir)
        // 旧存档没有这个字段，缺省当传送带处理
        lineType = try c.decodeIfPresent(LineType.self, forKey: .lineType) ?? .belt
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(cell.col)
        hasher.combine(cell.row)
        hasher.combine(axis.rawValue)
        hasher.combine(lineType.rawValue)
    }
    static func == (lhs: BeltSegment, rhs: BeltSegment) -> Bool {
        lhs.cell == rhs.cell && lhs.axis == rhs.axis && lhs.lineType == rhs.lineType
    }
}

// MARK: - 单条传送带（有序段列表，同一条内 lineType 始终一致）
struct Belt: Identifiable, Codable {
    let id: UUID
    var segments: [BeltSegment]   // 有序，首尾相连

    init(segments: [BeltSegment]) {
        self.id = UUID()
        self.segments = segments
    }

    var isEmpty: Bool { segments.isEmpty }
    var lineType: LineType { segments.first?.lineType ?? .belt }

    /// 终点格：最后一段本身所在的格
    var tailCell: GridPoint? { segments.last?.cell }

    /// 起点格：第一段所在格
    var headCell: GridPoint? { segments.first?.cell }

    /// 末端衔接范围：末端格本身 + 四周四格 + 前一格
    var tailNeighborhood: Set<String> {
        guard let tail = tailCell else { return [] }
        var cells = [(0,0),(1,0),(-1,0),(0,1),(0,-1)].map { dx, dy in
            "\(tail.col + dx),\(tail.row + dy)"
        }
        if let last = segments.last {
            let prev = GridPoint(col: tail.col - last.toDir.col,
                                 row: tail.row - last.toDir.row)
            cells.append("\(prev.col),\(prev.row)")
        }
        return Set(cells)
    }

    /// 起点衔接范围：起点格本身 + 四周四格 + 后一格
    var headNeighborhood: Set<String> {
        guard let head = headCell else { return [] }
        var cells = [(0,0),(1,0),(-1,0),(0,1),(0,-1)].map { dx, dy in
            "\(head.col + dx),\(head.row + dy)"
        }
        if let first = segments.first {
            let next = GridPoint(col: head.col + first.toDir.col,
                                 row: head.row + first.toDir.row)
            cells.append("\(next.col),\(next.row)")
        }
        return Set(cells)
    }
}

// MARK: - 传送带网络（多条带 + 十字交叉）
struct BeltNetwork: Codable {
    var belts: [Belt] = []

    var isEmpty: Bool { belts.isEmpty }

    /// 所有段的扁平视图（用于渲染）
    var allSegments: [BeltSegment] { belts.flatMap { $0.segments } }

    /// 某格是否有任意传送带段
    func hasBelt(at cell: GridPoint) -> Bool {
        belts.contains { $0.segments.contains { $0.cell == cell } }
    }

    /// 某格所属的所有带 ID（十字格可能属于多条带）
    func beltIDs(at cell: GridPoint) -> [UUID] {
        belts.filter { $0.segments.contains { $0.cell == cell } }.map { $0.id }
    }
}

// MARK: - 仓库取线机制
// "仓库取货口"(unloader_1)/"仓库存货口"(loader_1)/"仓库存取线源桩"(log_hongs_bus_source)/
// "仓库存取线基段"(log_hongs_bus) 都已经在 devices_generated.json 的仓储存取分类里了，不用手写；
// 只是 JSON 本身不知道"源桩/基段是武陵专属机制"这件事，需要手动覆盖它们的 allowedMaps
extension BuildingDefinition {
    /// 仓库取货口：只出，取货具体是什么材料由 PlacedBuilding.outletMaterial 决定
    static let warehouseOutletID = "unloader_1"
    /// 仓库存货口：只入，接收传送带送来的任意材料存进仓库，不需要额外配置
    static let warehouseInletID = "loader_1"
    /// 仓库取线相关的两个口，地图专属摆放规则对这两个都生效
    static let warehousePortIDs: Set<String> = [warehouseOutletID, warehouseInletID]

    /// 武陵专属：仓库存取线源桩——取货口/存货口最终都要挂在这套线上的根
    static let warehouseSourceID = "log_hongs_bus_source"
    /// 武陵专属：仓库存取线基段——必须连着源桩，取货口/存货口再连到基段上
    static let warehouseBaseSegmentID = "log_hongs_bus"

    /// JSON 数据本身不带"这个建筑只有武陵能用"这种地图限定信息，这里按实际游戏机制手动覆盖
    private static let mapOverrides: [String: Set<MapType>] = [
        warehouseSourceID: [.wuling],
        warehouseBaseSegmentID: [.wuling],
    ]
}

// MARK: - 建筑库（从 devices_generated.json 解析，叠加地图限定覆盖）
extension BuildingDefinition {
    static let all: [BuildingDefinition] = BuildingParser.loadAll().map { def in
        guard let override = mapOverrides[def.id] else { return def }
        return BuildingDefinition(
            id: def.id, name: def.name, category: def.category,
            size: def.size, powerUsage: def.powerUsage, ports: def.ports,
            allowedMaps: override
        )
    }

    static func find(_ id: String) -> BuildingDefinition? {
        all.first { $0.id == id }
    }
}
