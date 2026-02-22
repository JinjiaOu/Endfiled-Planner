//
//  Recipe.swift
//  EndfiledPlanner
//
//  Created by Jinjia Ou on 2/14/26.
//

import Foundation

struct Recipe {
    let machine: String
    let time: Int
    let inputs: [(name: String, count: Int)]
    let outputCount: Int
}
