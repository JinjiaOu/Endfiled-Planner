//
//  BlueprintModels.swift
//  EndfiledPlanner
//
//  Created by Jinjia Ou on 2/21/26.
//

import Foundation

// MARK: - 蓝图集响应

struct BlueprintSetsResponse: Codable {
    let version: String
    let lastUpdated: String
    let blueprintSets: [BlueprintSet]
}

// MARK: - 蓝图集

struct BlueprintSet: Identifiable, Codable {
    let id: String
    let name: String
    let author: String
    let region: String
    let location: String
    let description: String
    let blueprints: [BlueprintItem]
}

// MARK: - 单个蓝图

struct BlueprintItem: Identifiable, Codable {
    let id: String
    let order: Int
    let name: String
    let code: String
    let notes: String
}
