//
//  FactoryGridModel.swift
//  EndfiledPlanner
//
//  Created by Jinjia Ou on 4/3/26.
//

import Foundation

// MARK: - 布局快照（用于序列化）
struct FactoryLayout: Codable {
    var buildings: [PlacedBuilding]
    var beltNetwork: BeltNetwork
    var savedAt: Date

    static let empty = FactoryLayout(buildings: [], beltNetwork: BeltNetwork(), savedAt: .now)
}

// MARK: - 网格模型
class FactoryGridModel {

    static let gridCols = 30
    static let gridRows = 24

    // MARK: - 保存/读取（UserDefaults）
    private static let saveKey = "factory_layout_v1"

    static func save(_ layout: FactoryLayout) {
        if let data = try? JSONEncoder().encode(layout) {
            UserDefaults.standard.set(data, forKey: saveKey)
        }
    }

    static func load() -> FactoryLayout {
        guard let data = UserDefaults.standard.data(forKey: saveKey),
              let layout = try? JSONDecoder().decode(FactoryLayout.self, from: data)
        else { return .empty }
        return layout
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: saveKey)
    }

    // MARK: - 碰撞检测
    /// 检查新建筑是否与已有建筑重叠
    static func canPlace(
        definition: BuildingDefinition,
        at origin: GridPoint,
        rotation: BuildingRotation,
        existing: [PlacedBuilding]
    ) -> Bool {
        let dummy = PlacedBuilding(definitionID: definition.id, origin: origin, rotation: rotation)
        let newCells = Set(dummy.occupiedCells(definition: definition).map { "\($0.col),\($0.row)" })

        // 边界检查
        let size = dummy.effectiveSize(definition: definition)
        if origin.col < 0 || origin.row < 0 { return false }
        if origin.col + size.width > gridCols { return false }
        if origin.row + size.height > gridRows { return false }

        // 碰撞检查
        for placed in existing {
            guard let def = BuildingDefinition.find(placed.definitionID) else { continue }
            let occupiedCells = Set(placed.occupiedCells(definition: def).map { "\($0.col),\($0.row)" })
            if !newCells.isDisjoint(with: occupiedCells) { return false }
        }
        return true
    }

    // MARK: - 产线分析
    struct ProductionStats {
        let totalPower: Double          // 总功率消耗 (MW)
        let buildingCount: Int
        let categoryBreakdown: [BuildingCategory: Int]
        let bottleneck: String?         // 瓶颈建筑名称
        let productionLines: [ProductionLine]
    }

    struct ProductionLine {
        let output: String
        let ratePerMin: Double
        let buildingNames: [String]
    }

    static func analyze(layout: FactoryLayout) -> ProductionStats {
        var totalPower = 0.0
        var categoryBreakdown: [BuildingCategory: Int] = [:]
        var outputRates: [String: (rate: Double, buildings: [String])] = [:]
        var minEfficiency = Double.infinity
        var bottleneck: String? = nil

        for placed in layout.buildings where placed.isActive {
            guard let def = BuildingDefinition.find(placed.definitionID) else { continue }

            totalPower += def.powerUsage
            categoryBreakdown[def.category, default: 0] += 1

            if let output = def.output, def.productionRate > 0 {
                var entry = outputRates[output] ?? (rate: 0, buildings: [])
                entry.rate += def.productionRate
                entry.buildings.append(def.name)
                outputRates[output] = entry

                // 简单瓶颈检测：找产率最低的非零建筑
                if def.productionRate < minEfficiency {
                    minEfficiency = def.productionRate
                    bottleneck = def.name
                }
            }
        }

        let lines = outputRates.map { key, value in
            ProductionLine(output: key, ratePerMin: value.rate, buildingNames: value.buildings)
        }.sorted { $0.ratePerMin > $1.ratePerMin }

        return ProductionStats(
            totalPower: totalPower,
            buildingCount: layout.buildings.count,
            categoryBreakdown: categoryBreakdown,
            bottleneck: layout.buildings.count > 1 ? bottleneck : nil,
            productionLines: lines
        )
    }
}
