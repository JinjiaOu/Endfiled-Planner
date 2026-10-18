// Created by Jinjia Ou on 10/1/26.

import SwiftUI
import UIKit

struct ItemIcon: View {
    let name: String
    let size: CGFloat

    private static let fallbacks: [String: String] = {
        DataPackStore.decode([String: String].self, resource: "icon_fallbacks") ?? [:]
    }()

    /// 先找自己的图、再找借用的空容器图；每个 id 先看下载的数据包（DataPackStore），再看安装包
    private var image: Image? {
        guard let item = ItemCatalog.byName[name] else { return nil }
        for id in [item.itemId, Self.fallbacks[item.itemId]].compactMap({ $0 }) {
            if let downloaded = DataPackStore.icon(for: id) { return Image(uiImage: downloaded) }
            if UIImage(named: id) != nil { return Image(id) }
        }
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
            if let image {
                image
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
