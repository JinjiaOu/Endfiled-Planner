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
                if let result = parseRecipeLine(line) {
                    recipes[result.outputName, default: []].append(result.recipe)
                }
            }
        }
    }
    
    private func parseRecipeLine(_ line: String)
    -> (outputName: String, recipe: Recipe)? {
        
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
        
        var inputs: [(String, Int)] = []
        
        if !inputPart.isEmpty {
            for mat in inputPart.components(separatedBy: "+") {
                let trimmed = mat.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { continue }
                
                let parts = trimmed.components(separatedBy: "x")
                let name = parts[0].trimmingCharacters(in: .whitespaces)
                let count = parts.count > 1 ? Int(parts[1]) ?? 1 : 1
                inputs.append((name, count))
            }
        }
        
        let outputParts = outputPart.components(separatedBy: "x")
        let outputName = outputParts[0].trimmingCharacters(in: .whitespaces)
        let outputCount = outputParts.count > 1 ? Int(outputParts[1]) ?? 1 : 1
        
        let recipe = Recipe(
            machine: machine,
            time: time,
            inputs: inputs,
            outputCount: outputCount
        )
        
        return (outputName, recipe)
    }
    
    func buildTree(target: String, amount: Int = 1) {
        rootNode = createNode(name: target,
                              amount: amount,
                              visited: [])
        layoutTree()
    }
    
    private func createNode(
        name: String,
        amount: Int,
        visited: Set<String>
    ) -> RecipeNode {
        
        if visited.contains(name) {
            return RecipeNode(name: name, amount: amount, recipe: nil)
        }
        
        guard let recipe = recipes[name]?.first else {
            return RecipeNode(name: name, amount: amount, recipe: nil)
        }
        
        let node = RecipeNode(name: name, amount: amount, recipe: recipe)
        
        let batches = Int(ceil(Double(amount) / Double(recipe.outputCount)))
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
        
        node.totalTime = recipe.time * batches +
            (node.children.map { $0.totalTime }.max() ?? 0)
        
        return node
    }
    
    // 垂直布局
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
                assignPosition(node: child,
                               level: level + 1,
                               xCounter: &xCounter)
            }
            
            let minX = node.children.map { $0.positionX }.min() ?? 0
            let maxX = node.children.map { $0.positionX }.max() ?? 0
            node.positionX = (minX + maxX) / 2
        }
    }
}
