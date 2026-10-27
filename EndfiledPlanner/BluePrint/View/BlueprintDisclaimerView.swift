// Created by Jinjia Ou on 2/22/26.

import SwiftUI

struct BlueprintDisclaimerView: View {
    @Binding var isPresented: Bool
    @AppStorage("hasAcceptedBlueprintDisclaimer") private var hasAccepted = false

    var body: some View {
        AppNoticeDialog(title: String(localized: "蓝图分享免责声明")) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                DisclaimerItem(
                    number: "1",
                    title: String(localized: "内容来源"),
                    content: String(localized: "本应用中的所有蓝图分享码均来自社区玩家自发贡献，开发者仅提供展示平台。")
                )
                
                // 条款2
                DisclaimerItem(
                    number: "2",
                    title: String(localized: "使用风险"),
                    content: "蓝图使用前请自行测试和验证，开发者不对蓝图的正确性、完整性或适用性做任何保证。使用蓝图导致的任何游戏内损失由玩家自行承担。"
                )
                
                // 条款3
                DisclaimerItem(
                    number: "3",
                    title: String(localized: "知识产权"),
                    content: "所有蓝图的知识产权归原作者所有。本应用仅作为展示平台，不主张任何蓝图的所有权。"
                )
                
                // 条款4
                DisclaimerItem(
                    number: "4",
                    title: String(localized: "内容审核"),
                    content: "虽然我们尽力审核蓝图内容，但无法保证所有内容的准确性。如发现问题蓝图，请及时反馈。"
                )
                
                // 条款5
                DisclaimerItem(
                    number: "5",
                    title: String(localized: "游戏数据"),
                    content: "本应用为《明日方舟：终末地》游戏的非官方辅助工具，所有内容均为虚拟游戏数据，与现实无关。"
                )

            }
        } actions: {
            VStack(spacing: AppSpacing.xs) {
                Button(action: acceptAndContinue) {
                    Label(String(localized: "我已阅读并同意"), systemImage: "checkmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(AppActionStyle())
                Button(String(localized: "取消")) { isPresented = false }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(AppActionStyle(emphasis: .secondary))
            }
        }
    }

    private func acceptAndContinue() {
        hasAccepted = true
        isPresented = false
    }
}

struct DisclaimerItem: View {
    let number: String
    let title: String
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
                Text(number).font(AppTypography.numeric).foregroundStyle(AppColors.accent)
                Text(title).font(AppTypography.rowTitle).foregroundStyle(AppColors.primaryText)
            }
            Text(content).font(AppTypography.body).foregroundStyle(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview { BlueprintDisclaimerView(isPresented: .constant(true)) }
