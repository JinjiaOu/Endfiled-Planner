//
//  EndfiledPlannerApp.swift
//  EndfiledPlanner
//
//  Created by Jinjia Ou on 2/14/26.
//

import SwiftUI

@main
struct EndfiledPlannerApp: App {
    init() {
        // 上次下载好的数据包 / 恢复内置要在任何数据被读之前处理
        DataPackStore.prepare()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task { await DataPackUpdater.shared.check(silent: true) }
        }
    }
}
