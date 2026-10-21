// Created by Jinjia Ou on 2/14/26.

import SwiftUI

/// 首页为唯一功能入口，各模块共用原生导航栈。
enum AppSection: Hashable {
    case recipes, blueprints, factory, calculator
}

struct ContentView: View {
    @State private var path: [AppSection] = []
    @State private var factoryEntryID = UUID()
    // 由导航根持有，退出基建不会销毁尚未保存的布局与撤销记录。
    @StateObject private var factoryViewModel = FactoryViewModel()

    var body: some View {
        NavigationStack(path: $path) {
            HomeView { section in
                if section == .factory { factoryEntryID = UUID() }
                path.append(section)
            }
            .navigationDestination(for: AppSection.self) { section in
                switch section {
                case .recipes:
                    SearchView()
                case .blueprints:
                    BlueprintSetView()
                case .calculator:
                    ProductionCalculatorView()
                case .factory:
                    FactoryLayoutView(onExit: { path.removeAll() }, entryID: factoryEntryID,
                                      viewModel: factoryViewModel)
                }
            }
        }
        .tint(AppColors.accent)
    }
}

#Preview { ContentView() }
