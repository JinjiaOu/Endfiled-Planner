// Created by Jinjia Ou on 10/1/26.

import SwiftUI
import UIKit

struct ItemIcon: View {
    let name: String
    let size: CGFloat

    private struct Item: Decodable {
        let itemId: String
        let name: String
        let phase: String
    }

    private static func load<T: Decodable>(_ resource: String, as type: T.Type) -> T? {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static let itemsByName: [String: Item] = {
        let items = load("items", as: [Item].self) ?? []
        return Dictionary(items.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
    }()
    private static let fallbacks = load("icon_fallbacks", as: [String: String].self) ?? [:]

    private var assetID: String? {
        guard let item = Self.itemsByName[name] else { return nil }
        if UIImage(named: item.itemId) != nil { return item.itemId }
        if let baseID = Self.fallbacks[item.itemId], UIImage(named: baseID) != nil { return baseID }
        return nil
    }

    private var placeholder: String {
        switch Self.itemsByName[name]?.phase {
        case "liquid": return "drop"
        case "gas": return "cloud"
        default: return "cube"
        }
    }

    var body: some View {
        Group {
            if let assetID {
                Image(assetID)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: placeholder)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .padding(size * 0.15)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
