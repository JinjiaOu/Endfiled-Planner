//
//  NodeView.swift
//  EndfiledPlanner
//
//  Created by Jinjia Ou on 2/14/26.
//

import SwiftUI

struct NodeView: View {
    
    let node: RecipeNode
    
    var body: some View {
        VStack(spacing: 6) {
            
            Text(node.name)
                .font(.headline)
            
            Text("x\(node.amount)")
                .font(.subheadline)
                .foregroundColor(.gray)
            
            if let recipe = node.recipe {
                Text(recipe.machine)
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
        .padding()
        .background(node.recipe == nil
                    ? Color.orange.opacity(0.2)
                    : Color.blue.opacity(0.2))
        .cornerRadius(10)
    }
}
