// Created by Jinjia Ou on 10/17/26.

import SwiftUI

/// 与设置页共享同一个更新器；这里只接入设计系统，不改变下载或启用时机。
struct DataUpdateBanner: View {
    @ObservedObject private var updater = DataPackUpdater.shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        switch updater.state {
        case .available(let remote):
            AppSurface {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        availableMessage(date: remote.builtDateText)
                        downloadButton
                    }
                } else {
                    HStack(alignment: .center, spacing: AppSpacing.sm) {
                        availableMessage(date: remote.builtDateText)
                        downloadButton.fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
        case .downloading(let done, let total):
            AppSurface {
                AppLoadingState(title: "正在下载游戏数据",
                                progress: Double(done) / Double(max(total, 1)),
                                detail: "\(done)/\(total)")
            }
        case .readyToRestart:
            AppSurface {
                AppInlineNotice(title: "游戏数据已就绪", message: "完全退出并重新打开 App 后生效", tone: .success)
            }
        default:
            EmptyView()
        }
    }

    private func availableMessage(date: String) -> some View {
        AppInlineNotice(title: "发现新的游戏数据", message: "\(date) · 配方/物品/图标", tone: .info)
    }

    private var downloadButton: some View {
        Button {
            Task { await updater.download() }
        } label: {
            Label("下载", systemImage: "arrow.down")
        }
        .buttonStyle(AppActionStyle())
    }
}
