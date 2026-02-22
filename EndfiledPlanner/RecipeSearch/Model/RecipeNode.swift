//
//  RecipeNode.swift
//  EndfiledPlanner
//
//  Created by Jinjia Ou on 2/14/26.
//

import Foundation

class RecipeNode: Identifiable {
    let id = UUID()
    let name: String
    let amount: Int
    let recipe: Recipe?
    
    var children: [RecipeNode] = []
    var batches: Int = 1
    var totalTime: Int = 0
    
    // 垂直布局用
    var level: Int = 0
    var positionX: CGFloat = 0
    
    init(name: String, amount: Int, recipe: Recipe?) {
        self.name = name
        self.amount = amount
        self.recipe = recipe
    }
}
