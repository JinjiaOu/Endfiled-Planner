//
//  RecipeViewModel.swift
//  EndfiledPlanner
//
//  Created by Jinjia Ou on 2/14/26.
//

import Foundation
import Combine

class RecipeViewModel: ObservableObject {
    
    @Published var recipes: [String: [Recipe]] = [:]
    @Published var rootNode: RecipeNode?
    
    init() {
        loadRecipes()
    }
    
    func loadRecipes() {
        guard let url = Bundle.main.url(forResource: "recipes", withExtension: "txt") else {
            print("未找到 recipes.txt")
            return
        }
        do {
            let content = try String(contentsOf: url)
            parseRecipes(content)
            print("已加载配方数量:", recipes.count)
        } catch {
            print("读取失败:", error)
        }
    }
    
    private func parseRecipes(_ text: String) {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        
        let blocks = normalized.components(separatedBy: "\n\n")
        
        for block in blocks {
            let lines = block
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            
            guard lines.count > 1 else { continue }
            
            for line in lines.dropFirst() {
                if let recipe = parseRecipeLine(line) {
                    for output in recipe.outputs {
                        recipes[output.name, default: []].append(recipe)
                    }
                }
            }
        }
    }
    
    private func parseRecipeLine(_ line: String) -> Recipe? {
        guard let pipeIndex = line.firstIndex(of: "|") else { return nil }
        
        let left = String(line[..<pipeIndex]).trimmingCharacters(in: .whitespaces)
        let right = String(line[line.index(after: pipeIndex)...]).trimmingCharacters(in: .whitespaces)
        
        let leftParts = left.components(separatedBy: " ")
        guard leftParts.count >= 2 else { return nil }
        
        guard let timeString = leftParts.last?.replacingOccurrences(of: "s", with: ""),
              let time = Int(timeString) else { return nil }
        
        let machine = leftParts.dropLast().joined(separator: " ")
        
        let components = right.components(separatedBy: "->")
        guard components.count == 2 else { return nil }
        
        let inputPart = components[0].trimmingCharacters(in: .whitespaces)
        let outputPart = components[1].trimmingCharacters(in: .whitespaces)
        
        // 解析输入
        var inputs: [(name: String, count: Int)] = []
        if !inputPart.isEmpty {
            for mat in inputPart.components(separatedBy: "+") {
                let trimmed = mat.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { continue }
                let parts = trimmed.components(separatedBy: "x")
                let name = parts[0].trimmingCharacters(in: .whitespaces)
                let count = parts.count > 1 ? Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 1 : 1
                inputs.append((name, count))
            }
        }
        
        // 解析多输出
        var outputs: [(name: String, count: Int)] = []
        for out in outputPart.components(separatedBy: "+") {
            let trimmed = out.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            let parts = trimmed.components(separatedBy: "x")
            let name = parts[0].trimmingCharacters(in: .whitespaces)
            let count = parts.count > 1 ? Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 1 : 1
            outputs.append((name, count))
        }
        
        guard !outputs.isEmpty else { return nil }
        
        return Recipe(machine: machine, time: time, inputs: inputs, outputs: outputs)
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
    
    /// 按机器名分组去重后的配方表，供生产优化模块给某台放置的建筑挑选配方用
    /// 顺序按第一个产物名排序，保证同一份数据每次算出来的下标都一样
    func recipesByMachine() -> [String: [Recipe]] {
        var seen = Set<String>()
        var result: [String: [Recipe]] = [:]
        for list in recipes.values {
            for r in list {
                guard !seen.contains(r.signature) else { continue }
                seen.insert(r.signature)
                result[r.machine, default: []].append(r)
            }
        }
        for key in result.keys {
            result[key]?.sort { ($0.outputs.first?.name ?? "") < ($1.outputs.first?.name ?? "") }
        }
        return result
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
