//
//  RecipeViewModel.swift
//  EndfiledPlanner
//
//  Created by Jinjia Ou on 2/14/26.
//

import Foundation
import Combine

class RecipeViewModel: ObservableObject {
    
    /// 按产物名分组（多产物配方在每个产物下各出现一次），配方查询页用
    @Published var recipes: [String: [Recipe]] = [:]
    @Published var rootNode: RecipeNode?
    /// recipes.json 原始顺序的全部配方
    private(set) var allRecipes: [Recipe] = []

    init() {
        loadRecipes()
    }

    // MARK: - recipes.json 原始结构
    private struct RecipesFile: Decodable {
        let recipes: [RecipeRecord]
    }

    private struct RecipeRecord: Decodable {
        let id: String
        let machineId: String
        let machineName: String
        let seconds: Double
        let gasEnvName: String?
        let ingredients: [ItemRecord]
        let outcomes: [ItemRecord]
    }

    private struct ItemRecord: Decodable {
        let itemId: String
        let name: String
        let count: Int
    }

    func loadRecipes() {
        guard let url = Bundle.main.url(forResource: "recipes", withExtension: "json") else {
            print("未找到 recipes.json")
            return
        }
        do {
            let file = try JSONDecoder().decode(RecipesFile.self, from: Data(contentsOf: url))
            allRecipes = file.recipes.compactMap(makeRecipe)
            var grouped: [String: [Recipe]] = [:]
            for recipe in allRecipes {
                for output in recipe.outputs {
                    grouped[output.name, default: []].append(recipe)
                }
            }
            recipes = grouped
            print("已加载配方数量:", allRecipes.count)
        } catch {
            print("读取失败:", error)
        }
    }

    private func makeRecipe(_ record: RecipeRecord) -> Recipe? {
        guard !record.outcomes.isEmpty else { return nil }
        let env = record.gasEnvName.flatMap { $0.isEmpty ? nil : $0 }
        let toItems = { (items: [ItemRecord]) in items.map { RecipeItem(itemId: $0.itemId, name: $0.name, count: $0.count) } }
        return Recipe(
            id: record.id,
            machineId: record.machineId,
            machine: env.map { "\(record.machineName)（\($0)）" } ?? record.machineName,
            time: Int(record.seconds.rounded()),
            gasEnvName: env,
            inputs: toItems(record.ingredients),
            outputs: toItems(record.outcomes)
        )
    }
    
    func buildTree(target: String, amount: Int = 1) {
        rootNode = createNode(name: target, amount: amount, visited: [])
        layoutTree()
        if let root = rootNode {
                print("根节点: \(root.name), positionX: \(root.positionX), level: \(root.level), children: \(root.children.count)")
            }
    }
    
    private func printTree(_ node: RecipeNode, indent: Int) {
        let pad = String(repeating: "  ", count: indent)
        print("\(pad)\(node.name) posX:\(node.positionX) level:\(node.level)")
        for child in node.children {
            printTree(child, indent: indent + 1)
        }
    }
    
    /// 按建筑 id（machineId）分组的配方表，供生产优化模块给某台放置的建筑挑选配方用。
    /// 存档记的是配方 ID，这里的顺序只影响列表展示：按第一个产物名、再按 ID 排，保证每次一样。
    /// 水泵只能抽清水这类数据修正已经在 Tools/gen_datapack.py 里做掉了
    func recipesByMachine() -> [String: [Recipe]] {
        var result = Dictionary(grouping: allRecipes, by: \.machineId)
        for key in result.keys {
            result[key]?.sort { ($0.outputName, $0.id) < ($1.outputName, $1.id) }
        }
        return result
    }

    /// 取线出口的材料选择列表：配方产物里所有固体，按名字排序
    func solidOutputs() -> [ItemInfo] {
        recipes.keys.compactMap { ItemCatalog.byName[$0] }.filter { $0.phase == .solid }.sorted { $0.name < $1.name }
    }

    static func isMiningMachine(_ machine: String) -> Bool {
        machine.contains("矿机") ||
        machine.contains("水驱矿机") ||
        machine.contains("水泵") ||
        machine.contains("采种机") ||
        machine.contains("种植机")
    }
    
    /// 判断某条配方是否与自己的产物构成互相依赖的循环
    /// （例如 息壤气 用息壤生产，而息壤又用息壤气生产）
    private func isCyclic(_ recipe: Recipe, producing name: String) -> Bool {
        recipe.inputs.contains { input in
            recipes[input.name]?.contains { $0.inputs.contains { $0.name == name } } ?? false
        }
    }

    /// 选出生产该物品最合适的配方：优先选不构成循环依赖的配方，
    /// 都不构成循环或都构成循环时再按耗时取最短
    private func pickRecipe(for name: String) -> Recipe? {
        guard let candidates = recipes[name], !candidates.isEmpty else { return nil }
        let nonCyclic = candidates.filter { !isCyclic($0, producing: name) }
        let pool = nonCyclic.isEmpty ? candidates : nonCyclic
        return pool.min(by: { $0.time < $1.time })
    }

    private func createNode(
        name: String,
        amount: Int,
        visited: Set<String>
    ) -> RecipeNode {

        if visited.contains(name) {
            return RecipeNode(name: name, amount: amount, recipe: nil)
        }

        guard let recipe = pickRecipe(for: name) else {
            return RecipeNode(name: name, amount: amount, recipe: nil)
        }
        
        let node = RecipeNode(name: name, amount: amount, recipe: recipe)
        
        // 找到目标输出的数量
        let targetOutput = recipe.outputs.first { $0.name == name }
        let outCount = targetOutput?.count ?? 1
        let batches = Int(ceil(Double(amount) / Double(outCount)))
        node.batches = batches
        
        var newVisited = visited
        newVisited.insert(name)
        
        for input in recipe.inputs {
            let childAmount = input.count * batches
            let childNode = createNode(
                name: input.name,
                amount: childAmount,
                visited: newVisited
            )
            node.children.append(childNode)
        }
        
        let selfTime = RecipeViewModel.isMiningMachine(recipe.machine) ? 0 : recipe.time * batches
        node.totalTime = selfTime + (node.children.map { $0.totalTime }.max() ?? 0)
        
        return node
    }
    
    private func layoutTree() {
        guard let root = rootNode else { return }
        var xCounter: CGFloat = 0
        assignPosition(node: root, level: 0, xCounter: &xCounter)
    }
    
    private func assignPosition(
        node: RecipeNode,
        level: Int,
        xCounter: inout CGFloat
    ) {
        node.level = level
        
        if node.children.isEmpty {
            node.positionX = xCounter
            xCounter += 1
        } else {
            for child in node.children {
                assignPosition(node: child, level: level + 1, xCounter: &xCounter)
            }
            let minX = node.children.map { $0.positionX }.min() ?? 0
            let maxX = node.children.map { $0.positionX }.max() ?? 0
            node.positionX = (minX + maxX) / 2
        }
    }
}
