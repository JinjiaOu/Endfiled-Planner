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

    /// - Parameter machineRecipes: 按机器名分组去重的配方表（RecipeViewModel.recipesByMachine()），
    ///   selectedRecipeIndex 就是这个表里对应机器那份列表的下标
    static func analyze(layout: FactoryLayout, machineRecipes: [String: [Recipe]]) -> ProductionStats {
        var totalPower = 0.0
        var categoryBreakdown: [BuildingCategory: Int] = [:]

        // V1：按"建筑类型 + 已选配方"分组，算每组的理论产出速率。
        // 不做传送带连通性分析，也不做瓶颈检测（瓶颈需要匹配下游消耗速率，工作量较大，先留空）。
        struct GroupKey: Hashable { let defID: String; let recipeIndex: Int }
        var groups: [GroupKey: Int] = [:]   // 每组建筑数量

        for placed in layout.buildings where placed.isActive {
            guard let def = BuildingDefinition.find(placed.definitionID) else { continue }
            totalPower += def.powerUsage
            categoryBreakdown[def.category, default: 0] += 1

            guard let idx = placed.selectedRecipeIndex else { continue }
            groups[GroupKey(defID: placed.definitionID, recipeIndex: idx), default: 0] += 1
        }

        var outputRates: [String: (rate: Double, buildings: [String])] = [:]
        for (key, count) in groups {
            guard let def = BuildingDefinition.find(key.defID),
                  let recipeList = machineRecipes[def.name],
                  key.recipeIndex >= 0, key.recipeIndex < recipeList.count
            else { continue }
            let recipe = recipeList[key.recipeIndex]
            // 挖矿类设备的耗时不计入生产链瓶颈判断，但产出速率本身仍然按配方算
            for output in recipe.outputs {
                let rate = (Double(output.count) / Double(recipe.time)) * 60 * Double(count)
                var entry = outputRates[output.name] ?? (rate: 0, buildings: [])
                entry.rate += rate
                entry.buildings.append("\(def.name) ×\(count)")
                outputRates[output.name] = entry
            }
        }

        let lines = outputRates.map { key, value in
            ProductionLine(output: key, ratePerMin: value.rate, buildingNames: value.buildings)
        }.sorted { $0.ratePerMin > $1.ratePerMin }

        return ProductionStats(
            totalPower: totalPower,
            buildingCount: layout.buildings.count,
            categoryBreakdown: categoryBreakdown,
            bottleneck: nil,
            productionLines: lines
        )
    }
}
