//
//  BuildingParser.swift
//  EndfiledPlanner
//
//  Created by Jinjia Ou on 8/27/26.
//

import Foundation

/// 解析 devices_generated.json（游戏解包数据转换而来，字段结构见该文件本身），
/// 产出真实的 BuildingDefinition 列表，替代原来手写的 mock 数据。
enum BuildingParser {

    // MARK: - JSON 原始结构
    private struct DevicesFile: Codable {
        let devices: [DeviceRecord]
    }

    private struct DeviceRecord: Codable {
        let id: String
        let name: String
        let recordType: String
        let categoryName: String
        let size: DeviceSize
        let powerConsume: Double?   // 物流网络节点（分流器/传送带本身等）没有这个字段
        let ports: [DevicePort]?
    }

    private struct DeviceSize: Codable {
        let width: Int
        let depth: Int
        let height: Int
    }

    private struct DevicePort: Codable {
        let direction: PortIODirection
        let kind: PortKind
        let position: DevicePoint
        let rotation: DevicePoint
    }

    private struct DevicePoint: Codable {
        let x: Int
        let y: Int
        let z: Int
    }

    /// 只导入和生产规划真正相关的分类，战斗辅助/功能设备（滑索架、留言信标等）不在此范围
    private static let categoryMap: [String: BuildingCategory] = [
        "资源开采": .extraction,
        "仓储存取": .storage,
        "基础生产": .production,
        "合成制造": .synthesis,
        "电力供应": .power,
    ]

    static func loadAll() -> [BuildingDefinition] {
        guard let url = Bundle.main.url(forResource: "devices_generated", withExtension: "json") else {
            print("未找到 devices_generated.json")
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            let file = try JSONDecoder().decode(DevicesFile.self, from: data)
            return file.devices.compactMap(parseDevice)
        } catch {
            print("建筑数据解析失败:", error)
            return []
        }
    }

    private static func parseDevice(_ device: DeviceRecord) -> BuildingDefinition? {
        // recordType == "logistic" 是传送带/管道本身及其分流/汇流节点，
        // 已经由现有的拖拽绘制系统覆盖，这里不作为可放置建筑导入
        guard device.recordType == "building" else { return nil }
        guard let category = categoryMap[device.categoryName] else { return nil }
        guard device.size.width > 0, device.size.depth > 0 else { return nil }

        let size = GridSize(width: device.size.width, height: device.size.depth)
        let ports = (device.ports ?? []).map { parsePort($0) }

        return BuildingDefinition(
            id: device.id,
            name: device.name,
            category: category,
            size: size,
            powerUsage: device.powerConsume ?? 0,
            ports: ports
        )
    }

    /// 端口的 rotation 字段记录的是"物流流动方向"，不是所在边：
    /// 输出口的流动方向 == 它所在边的朝外方向；输入口的流动方向是"流进建筑"，
    /// 与它所在边的朝外方向正好相反。已经用全部 77 个建筑的数据validate过这个换算关系。
    private static func parsePort(_ port: DevicePort) -> BuildingPort {
        let flowDirection = direction(fromDegrees: port.rotation.y)
        let edge = port.direction == .output ? flowDirection : opposite(flowDirection)

        // indexOnEdge 存原始网格偏移量（不是序号），上下边用 x，左右边用 z，
        // 因为有些建筑同一边的端口不是从 0 连续排列的（比如反应池的输入口在 x=1、x=3）
        let indexOnEdge: Int
        switch edge {
        case .up, .down:   indexOnEdge = port.position.x
        case .left, .right: indexOnEdge = port.position.z
        }

        return BuildingPort(kind: port.kind, ioDirection: port.direction, edge: edge, indexOnEdge: indexOnEdge)
    }

    private static func direction(fromDegrees y: Int) -> BuildingRotation {
        switch ((y % 360) + 360) % 360 {
        case 0:   return .down
        case 90:  return .right
        case 180: return .up
        case 270: return .left
        default:  return .down
        }
    }

    private static func opposite(_ d: BuildingRotation) -> BuildingRotation {
        BuildingRotation(rawValue: (d.rawValue + 2) % 4) ?? d
    }
}
