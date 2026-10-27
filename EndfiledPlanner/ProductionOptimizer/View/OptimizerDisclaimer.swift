// Created by Jinjia Ou on 10/17/26.

import SwiftUI

/// 打开生产优化模块时弹出的免责声明。每次进入弹一次，选"不再提示"后不再弹。
/// 单独做成 ViewModifier：FactoryLayoutView 的修饰链再加 .alert 会类型检查超时
struct OptimizerDisclaimerModifier: ViewModifier {
    /// 平级导航保留编辑器实例，通过进入标记延续原来每次进入的提示规则。
    var entryID: UUID? = nil
    @AppStorage("optimizerDisclaimerHidden") private var hidden = false
    @State private var showing = false
    /// 同一次进入只弹一次（从子页面、弹窗回来时 onAppear 会再触发）
    @State private var presented = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard !hidden, !presented else { return }
                presented = true
                showing = true
            }
            .onChange(of: entryID) { _, _ in
                guard !hidden else { return }
                presented = true
                showing = true
            }
            .alert(String(localized: "免责声明"), isPresented: $showing) {
                Button(String(localized: "我知道了"), role: .cancel) {}
                Button(String(localized: "不再提示")) { hidden = true }
            } message: {
                Text(String(localized: """
                本模块为玩家自制的非官方工具，与《明日方舟：终末地》官方无关。

                建筑和配方数据来自游戏解包与社区资料，产能、电力等结果是按简化规则模拟的估算，可能与游戏内实际表现不一致，请以游戏内为准。规划结果仅供参考。
                """))
            }
    }
}
