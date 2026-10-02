// Created by Jinjia Ou on 10/1/26.

import Foundation

enum ItemPhase: String, Decodable {
    case solid, liquid, gas
}

struct ItemInfo: Decodable, Hashable {
    let itemId: String
    let name: String
    let phase: ItemPhase
}

/// items.json（Tools/gen_datapack.py 生成）：配方里出现过的所有物品及形态，
/// 中文名在这份表里唯一，名字和 itemId 可以互查
enum ItemCatalog {
    static let all: [ItemInfo] = {
        guard let url = Bundle.main.url(forResource: "items", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([ItemInfo].self, from: data)
        else {
            print("未找到 items.json")
            return []
        }
        return items
    }()

    static let byName: [String: ItemInfo] = Dictionary(all.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
    static let byID: [String: ItemInfo] = Dictionary(all.map { ($0.itemId, $0) }, uniquingKeysWith: { first, _ in first })

    /// 能不能走传送带。表里查不到的名字按固体处理
    static func isSolid(_ name: String) -> Bool {
        (byName[name]?.phase ?? .solid) == .solid
    }

    static func name(for itemId: String) -> String? { byID[itemId]?.name }
    static func itemId(for name: String) -> String? { byName[name]?.itemId }
}

/// 热能池能烧的燃料（fuels.json，来自解包表 FactoryFuelItemTable）：
/// 烧哪种燃料就按哪种的 powerProvide 发电，每个燃料烧 secondsPerItem 秒
struct FuelInfo: Decodable {
    let itemId: String
    let name: String
    let powerProvide: Double
    let secondsPerItem: Double
}

enum FuelCatalog {
    private struct File: Decodable { let fuels: [FuelInfo] }

    static let all: [FuelInfo] = {
        guard let url = Bundle.main.url(forResource: "fuels", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data)
        else {
            print("未找到 fuels.json")
            return []
        }
        return file.fuels
    }()

    static let byName: [String: FuelInfo] = Dictionary(all.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
}
