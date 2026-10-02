// Created by Jinjia Ou on 10/1/26.

import SwiftUI
import UIKit

struct ItemIcon: View {
    let name: String
    let size: CGFloat

    private static let fallbacks: [String: String] = {
        guard let url = Bundle.main.url(forResource: "icon_fallbacks", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }()

    private var assetID: String? {
        guard let item = ItemCatalog.byName[name] else { return nil }
        if UIImage(named: item.itemId) != nil { return item.itemId }
        if let baseID = Self.fallbacks[item.itemId], UIImage(named: baseID) != nil { return baseID }
        return nil
    }

    private var placeholder: String {
        switch ItemCatalog.byName[name]?.phase {
        case .liquid: return "drop"
        case .gas: return "cloud"
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
