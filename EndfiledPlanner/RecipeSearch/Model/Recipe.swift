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
    let outputs: [(name: String, count: Int)]

    /// 机器名带"（稳定环境）"这类后缀的配方，需要附近有对应气体环境才能运行，返回"稳定"这样的环境名
    var requiredEnv: String? {
        guard let start = machine.range(of: "（"),
              let end = machine.range(of: "环境）", range: start.upperBound..<machine.endIndex)
        else { return nil }
        return String(machine[start.upperBound..<end.lowerBound])
    }

    var outputCount: Int { outputs.first?.count ?? 1 }
    var outputName: String { outputs.first?.name ?? "" }

    /// 用来在"同一个配方按不同产物存了好几份"的情况下去重（tuple 数组不能直接 Equatable）
    var signature: String {
        let i = inputs.map { "\($0.name)x\($0.count)" }.joined(separator: "+")
        let o = outputs.map { "\($0.name)x\($0.count)" }.joined(separator: "+")
        return "\(machine)|\(time)|\(i)->\(o)"
    }
}
