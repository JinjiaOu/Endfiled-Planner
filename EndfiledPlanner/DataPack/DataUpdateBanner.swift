// Created by Jinjia Ou on 10/17/26.

import SwiftUI

/// 首页的数据更新横幅：有新数据、下载中、下载完待重启时显示，其他时候不占位置。
/// 跟设置页 GAME DATA 区用同一个 DataPackUpdater，状态两边同步
struct DataUpdateBanner: View {
    @ObservedObject private var updater = DataPackUpdater.shared

    private let yellow = Color(red: 1.0, green: 0.8, blue: 0.0)
    private let green = Color(red: 0.4, green: 0.8, blue: 0.2)

    var body: some View {
        switch updater.state {
        case .available(let remote):
            card(accent: yellow) {
                icon("arrow.down.circle.fill", yellow)
                texts("发现新的游戏数据", "\(remote.builtDateText) · 配方/物品/图标")
                Spacer()
                Button {
                    Task { await updater.download() }
                } label: {
                    Text("下载")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(yellow)
                }
            }
        case .downloading(let done, let total):
            card(accent: yellow) {
                icon("arrow.down.circle", yellow)
                VStack(alignment: .leading, spacing: 6) {
                    Text("正在下载游戏数据 \(done)/\(total)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    ProgressView(value: Double(done), total: Double(max(total, 1))).tint(yellow)
                }
            }
        case .readyToRestart:
            card(accent: green) {
                icon("checkmark.circle.fill", green)
                texts("游戏数据已就绪", "完全退出并重新打开 App 后生效")
                Spacer()
            }
        default:
            EmptyView()
        }
    }

    private func card<Content: View>(accent: Color, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) { content() }
            .padding(14)
            .background(Color(red: 0.12, green: 0.13, blue: 0.16))
            .overlay(alignment: .leading) {
                Rectangle().fill(accent).frame(width: 3)
            }
            .overlay(Rectangle().stroke(accent.opacity(0.4), lineWidth: 1))
    }

    private func icon(_ name: String, _ color: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 26))
            .foregroundColor(color)
    }

    private func texts(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
            Text(subtitle)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
        }
    }
}
