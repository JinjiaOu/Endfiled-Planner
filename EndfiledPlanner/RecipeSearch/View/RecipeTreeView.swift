//
//  RecipeTreeView.swift
//  EndfiledPlanner
//
//  Created by Jinjia Ou on 2/14/26.
//

import SwiftUI

struct RecipeTreeView: View {
    
    let node: RecipeNode
    
    var body: some View {
        HStack(alignment: .center, spacing: 60) {
            
            ForEach(node.children) { child in
                RecipeTreeView(node: child)
            }
            
            NodeView(node: node)
        }
    }
}
