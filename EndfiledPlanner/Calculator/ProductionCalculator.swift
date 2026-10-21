// Created by Jinjia Ou on 10/21/26.

import Foundation

/// 目标产量计算：给一个产物和目标速率（个/分钟），沿配方往上游反推每一级要几台什么机器、原料要多少、总耗电。
/// 纯计算，跟基建规划画布无关。同一个物品在几条分支里都要时需求会合并（同一组机器一起算）。
enum ProductionCalculator {

    /// 一条生产步骤：某个物品用某条配方生产，需要多少、要几台机器
    struct Step: Identifiable {
        var id: String { item }
        let item: String
        let recipe: Recipe
        /// 需求速率（个/分钟），多条分支要的已经合并
        let ratePerMin: Double
        /// 精确台数（可能是小数），界面上取整显示
        let machines: Double
        /// 这台机器能选的配方数（>1 时界面给切换）
        let recipeChoices: Int
        /// 离目标产物的最大层数，用来排顺序（目标是 0）
        let depth: Int

        var machineCount: Int { Int((machines - 1e-9).rounded(.up)) }
    }

    struct Result {
        let target: String
        let steps: [Step]
        /// 不再往上游展开的原料（仓库原料、没有配方的物品、循环里断开的），个/分钟
        let raws: [(item: String, ratePerMin: Double)]
        /// 多产物配方顺带产出的副产物（个/分钟），没有拿来抵扣需求
        let byproducts: [(item: String, ratePerMin: Double)]
        /// 因为循环依赖没法再展开、被当成原料的物品
        let cycleBreaks: Set<String>
        /// 按台数取整算的总耗电（MW）
        let powerMW: Double
        var totalMachines: Int { steps.reduce(0) { $0 + $1.machineCount } }
    }

    /// 拆解机的配方是把装备拆回材料，不当成正常的生产路线
    private static let excludedMachineIDs: Set<String> = ["dismantler_1"]

    /// 某个物品能用的配方（产物里有它），排除拆解机
    static func candidates(for item: String, in recipes: [String: [Recipe]]) -> [Recipe] {
        (recipes[item] ?? []).filter { !excludedMachineIDs.contains($0.machineId) }
    }

    /// 默认当仓库原料、不往下展开：只能靠采集设备得到的固体（矿机挖的矿、种植机/采种机种的作物，
    /// 玩家一般从仓库取；水驱矿机虽然要吃水，也算采集）。
    /// 水和气虽然也来自水泵/气泵，默认展开，好算出要几台泵
    static func isDefaultRaw(_ item: String, in recipes: [String: [Recipe]]) -> Bool {
        let list = candidates(for: item, in: recipes)
        guard !list.isEmpty else { return true }
        let solid = ItemCatalog.byName[item]?.phase == .solid
        return solid && list.allSatisfy { RecipeViewModel.isMiningMachine($0.machine) }
    }

    /// 默认配方：优先不跟自己的产物构成循环的，再挑耗时最短的
    static func defaultRecipe(for item: String, in recipes: [String: [Recipe]]) -> Recipe? {
        let list = candidates(for: item, in: recipes)
        let nonCyclic = list.filter { recipe in
            !recipe.inputs.contains { input in
                candidates(for: input.name, in: recipes).contains { $0.inputs.contains { $0.name == item } }
            }
        }
        return (nonCyclic.isEmpty ? list : nonCyclic).min { $0.time < $1.time }
    }

    /// - Parameters:
    ///   - recipeChoice: 用户手动指定的配方（物品名 → 配方 ID）
    ///   - rawOverride: 用户手动指定"当原料"（true）或"展开生产"（false）的物品
    static func calculate(target: String, ratePerMin: Double,
                          recipes: [String: [Recipe]],
                          recipeChoice: [String: String],
                          rawOverride: [String: Bool]) -> Result {
        var demand: [String: Double] = [:]         // 每个物品的总需求（个/分钟）
        var chosen: [String: Recipe] = [:]
        var depth: [String: Int] = [:]
        var rawDemand: [String: Double] = [:]
        var byproducts: [String: Double] = [:]
        var cycleBreaks = Set<String>()

        func isRaw(_ item: String) -> Bool {
            if let forced = rawOverride[item] { return forced || candidates(for: item, in: recipes).isEmpty }
            return isDefaultRaw(item, in: recipes)
        }

        func recipe(for item: String) -> Recipe? {
            if let cached = chosen[item] { return cached }
            let list = candidates(for: item, in: recipes)
            let picked = recipeChoice[item].flatMap { id in list.first { $0.id == id } }
                ?? defaultRecipe(for: item, in: recipes)
            chosen[item] = picked
            return picked
        }

        // 需求是线性的：每次只把"新增的需求"沿配方往上游传，同一物品在多条分支里的需求自然累加
        func add(_ item: String, _ rate: Double, level: Int, path: Set<String>) {
            guard rate > 1e-12 else { return }
            if path.contains(item) {
                // 循环依赖：这一截当原料，不再往下展开
                cycleBreaks.insert(item)
                rawDemand[item, default: 0] += rate
                return
            }
            if isRaw(item) {
                rawDemand[item, default: 0] += rate
                return
            }
            guard let recipe = recipe(for: item),
                  let out = recipe.outputs.first(where: { $0.name == item }), out.count > 0 else {
                rawDemand[item, default: 0] += rate
                return
            }
            demand[item, default: 0] += rate
            depth[item] = max(depth[item] ?? 0, level)
            let craftsPerMin = rate / Double(out.count)
            for other in recipe.outputs where other.name != item {
                byproducts[other.name, default: 0] += craftsPerMin * Double(other.count)
            }
            var nextPath = path
            nextPath.insert(item)
            for input in recipe.inputs {
                add(input.name, craftsPerMin * Double(input.count), level: level + 1, path: nextPath)
            }
        }

        add(target, ratePerMin, level: 0, path: [])

        let steps: [Step] = demand.compactMap { item, rate in
            guard let recipe = chosen[item],
                  let out = recipe.outputs.first(where: { $0.name == item }) else { return nil }
            let craftsPerMin = rate / Double(out.count)
            let machines = craftsPerMin * Double(max(recipe.time, 1)) / 60
            return Step(item: item, recipe: recipe, ratePerMin: rate, machines: machines,
                        recipeChoices: candidates(for: item, in: recipes).count, depth: depth[item] ?? 0)
        }
        .sorted { ($0.depth, $0.item) < ($1.depth, $1.item) }

        let power = steps.reduce(0.0) { total, step in
            total + Double(step.machineCount) * (BuildingDefinition.find(step.recipe.machineId)?.powerUsage ?? 0)
        }

        func sortedPairs(_ dict: [String: Double]) -> [(item: String, ratePerMin: Double)] {
            dict.filter { $0.value > 1e-9 }.sorted { $0.key < $1.key }.map { (item: $0.key, ratePerMin: $0.value) }
        }

        return Result(target: target, steps: steps, raws: sortedPairs(rawDemand),
                      byproducts: sortedPairs(byproducts), cycleBreaks: cycleBreaks, powerMW: power)
    }
}
