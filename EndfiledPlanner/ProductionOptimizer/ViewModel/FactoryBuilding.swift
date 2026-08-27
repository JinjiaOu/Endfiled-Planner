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

// MARK: - 建筑定义（模板）
struct BuildingDefinition: Identifiable, Hashable {
    let id: String
    let name: String
    let category: BuildingCategory
    let size: GridSize          // 占格尺寸
    let productionRate: Double  // 每分钟产出数量
    let powerUsage: Double      // 功率（MW）
    let inputs: [String]        // 输入物品
    let output: String?         // 输出物品
    let description: String

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: BuildingDefinition, rhs: BuildingDefinition) -> Bool { lhs.id == rhs.id }
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

// MARK: - 传送带段（单格）
struct BeltSegment: Identifiable, Codable, Hashable {
    let id: UUID
    var cell: GridPoint
    var axis: BeltAxis
    var fromDir: GridPoint
    var toDir: GridPoint

    init(cell: GridPoint, axis: BeltAxis, fromDir: GridPoint, toDir: GridPoint) {
        self.id = UUID()
        self.cell = cell
        self.axis = axis
        self.fromDir = fromDir
        self.toDir = toDir
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(cell.col)
        hasher.combine(cell.row)
        hasher.combine(axis.rawValue)
    }
    static func == (lhs: BeltSegment, rhs: BeltSegment) -> Bool {
        lhs.cell == rhs.cell && lhs.axis == rhs.axis
    }
}

// MARK: - 单条传送带（有序段列表）
struct Belt: Identifiable, Codable {
    let id: UUID
    var segments: [BeltSegment]   // 有序，首尾相连

    init(segments: [BeltSegment]) {
        self.id = UUID()
        self.segments = segments
    }

    var isEmpty: Bool { segments.isEmpty }

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

// MARK: - Mock 建筑库
extension BuildingDefinition {
    static let all: [BuildingDefinition] = [
        // 采矿
        BuildingDefinition(
            id: "miner",
            name: "矿机",
            category: .extraction,
            size: GridSize(width: 2, height: 2),
            productionRate: 20,
            powerUsage: 0.3,
            inputs: [],
            output: "矿石",
            description: "自动采集地表矿物资源"
        ),
        // 冶炼
        BuildingDefinition(
            id: "smelter",
            name: "精炼炉",
            category: .production,
            size: GridSize(width: 2, height: 3),
            productionRate: 30,
            powerUsage: 1.2,
            inputs: ["矿石"],
            output: "精炼锭",
            description: "将矿石精炼为可用材料"
        ),
        // 加工
        BuildingDefinition(
            id: "crusher",
            name: "粉碎机",
            category: .synthesis,
            size: GridSize(width: 2, height: 2),
            productionRate: 25,
            powerUsage: 0.8,
            inputs: ["矿石"],
            output: "粉末",
            description: "将固体物料研磨成粉末"
        ),
        BuildingDefinition(
            id: "assembler",
            name: "装备原件机",
            category: .synthesis,
            size: GridSize(width: 3, height: 3),
            productionRate: 6,
            powerUsage: 2.5,
            inputs: ["精炼锭", "纤维"],
            output: "装备原件",
            description: "生产高级装备零件"
        ),
        BuildingDefinition(
            id: "shaper",
            name: "塑形机",
            category: .synthesis,
            size: GridSize(width: 2, height: 2),
            productionRate: 30,
            powerUsage: 0.9,
            inputs: ["精炼锭"],
            output: "瓶体",
            description: "将金属锭塑造成容器形状"
        ),
        BuildingDefinition(
            id: "grinder",
            name: "研磨机",
            category: .synthesis,
            size: GridSize(width: 2, height: 2),
            productionRate: 30,
            powerUsage: 0.7,
            inputs: ["粉末", "砂叶粉末"],
            output: "致密粉末",
            description: "高精度研磨，生产致密粉末材料"
        ),
        // 种植
        BuildingDefinition(
            id: "planter",
            name: "种植机",
            category: .synthesis,
            size: GridSize(width: 2, height: 3),
            productionRate: 30,
            powerUsage: 0.5,
            inputs: ["种子"],
            output: "作物",
            description: "自动化种植与收割作物"
        ),
        BuildingDefinition(
            id: "seeder",
            name: "采种机",
            category: .synthesis,
            size: GridSize(width: 2, height: 2),
            productionRate: 30,
            powerUsage: 0.4,
            inputs: ["作物"],
            output: "种子",
            description: "从成熟植物中采集种子"
        ),
        // 物流
        BuildingDefinition(
            id: "pump",
            name: "水泵",
            category: .extraction,
            size: GridSize(width: 1, height: 2),
            productionRate: 60,
            powerUsage: 0.2,
            inputs: [],
            output: "清水",
            description: "从环境中抽取清水"
        ),
        // 仓储
        BuildingDefinition(
            id: "warehouse",
            name: "仓库",
            category: .storage,
            size: GridSize(width: 2, height: 2),
            productionRate: 0,
            powerUsage: 0,
            inputs: [],
            output: nil,
            description: "存储各类生产物资"
        ),
    ]

    static func find(_ id: String) -> BuildingDefinition? {
        all.first { $0.id == id }
    }
}
