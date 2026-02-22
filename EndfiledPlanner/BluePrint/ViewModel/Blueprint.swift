//
//  Blueprint.swift
//  EndfiledPlanner
//
//  Created by Jinjia Ou on 2/21/26.
//

import Foundation

// MARK: - 蓝图数据模型（简化版）

struct BlueprintResponse: Codable {
    let version: String
    let lastUpdated: String
    let blueprints: [Blueprint]
}

struct Blueprint: Identifiable, Codable {
    let id: String
    let name: String
    let author: String
    let region: String
    let code: String
    let notes: String
}






