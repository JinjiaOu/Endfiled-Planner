//
//  Recipe.swift
//  EndfiledPlanner
//
//  Created by Jinjia Ou on 2/14/26.
//

import Foundation

struct RecipeItem {
    let itemId: String
    let name: String
    let count: Int
}

struct Recipe {
    /// recipes.json 里的配方 ID，存档按这个记，不再按列表下标
    let id: String
    /// 对应 devices.json 的建筑 id，生产规划按这个给建筑挑配方
    let machineId: String
    /// 展示用的机器名，需要气体环境的配方带"（稳定环境）"这类后缀，跟原来 recipes.txt 的写法一致
    let machine: String
    let time: Int
    /// 运行需要的气体环境（"稳定环境"等），不需要时为 nil
    let gasEnvName: String?
    /// 配方组（对应机器 modes 的 craftGroupId，用来判断是基础/液体/气体哪种模式的配方）
    var formulaGroupId: String? = nil
    let inputs: [RecipeItem]
    let outputs: [RecipeItem]

    /// 环境名去掉"环境"二字（"稳定环境"→"稳定"），跟 FlowSimulator.vaporizerGases 的取值对齐
    var requiredEnv: String? {
        guard let gasEnvName else { return nil }
        return gasEnvName.hasSuffix("环境") ? String(gasEnvName.dropLast(2)) : gasEnvName
    }

    var outputCount: Int { outputs.first?.count ?? 1 }
    var outputName: String { outputs.first?.name ?? "" }
}
