//
//  SettingsView.swift
//  EndfiledPlanner
//
//  Created by Jinjia Ou on 2/14/26.
//

import SwiftUI

struct SettingsView: View {
    
    @AppStorage("darkMode") private var darkMode = false
    @AppStorage("showGrid") private var showGrid = true
    @AppStorage("autoSave") private var autoSave = true
    @ObservedObject private var dataUpdater = DataPackUpdater.shared
    @State private var confirmRestore = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.08, green: 0.09, blue: 0.12)
                    .ignoresSafeArea()
                
                List {
                    
                    // 显示设置
                    Section {
                        Toggle(isOn: $showGrid) {
                            HStack {
                                Image(systemName: "square.grid.3x3")
                                    .foregroundColor(Color(red: 1.0, green: 0.8, blue: 0.0))
                                Text("网格背景")
                                    .foregroundColor(.white)
                            }
                        }
                        .tint(Color(red: 1.0, green: 0.8, blue: 0.0))
                    } header: {
                        Text("DISPLAY")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(red: 1.0, green: 0.8, blue: 0.0))
                    }
                    .listRowBackground(Color(red: 0.12, green: 0.13, blue: 0.16))
                    
                    // 功能设置
                    Section {
                        Toggle(isOn: $autoSave) {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                    .foregroundColor(Color(red: 0.4, green: 0.8, blue: 0.2))
                                Text("自动保存")
                                    .foregroundColor(.white)
                            }
                        }
                        .tint(Color(red: 0.4, green: 0.8, blue: 0.2))
                    } header: {
                        Text("FUNCTIONS")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(red: 0.4, green: 0.8, blue: 0.2))
                    }
                    .listRowBackground(Color(red: 0.12, green: 0.13, blue: 0.16))
                    
                    // 关于
                    Section {
                        HStack {
                            Text("VERSION")
                                .foregroundColor(.white.opacity(0.6))
                            Spacer()
                            Text("1.0.0")
                                .font(.system(size: 14, design: .monospaced))
                                .foregroundColor(Color(red: 1.0, green: 0.8, blue: 0.0))
                        }
                        
                        Button {
                            // 打开GitHub
                        } label: {
                            HStack {
                                Image(systemName: "link")
                                    .foregroundColor(Color(red: 1.0, green: 0.8, blue: 0.0))
                                Text("GitHub Repository")
                                    .foregroundColor(.white)
                            }
                        }
                        
                        Button {
                            // 反馈
                        } label: {
                            HStack {
                                Image(systemName: "exclamationmark.bubble")
                                    .foregroundColor(Color(red: 0.9, green: 0.5, blue: 0.2))
                                Text("Report Issue")
                                    .foregroundColor(.white)
                            }
                        }
                    } header: {
                        Text("ABOUT")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .listRowBackground(Color(red: 0.12, green: 0.13, blue: 0.16))
                    
                    // 游戏数据（配方/物品/建筑/图标）在线更新
                    Section {
                        HStack {
                            Text("数据版本")
                                .foregroundColor(.white.opacity(0.6))
                            Spacer()
                            Text(currentDataText)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(Color(red: 1.0, green: 0.8, blue: 0.0))
                        }

                        dataUpdateRow

                        if dataUpdater.canRestoreBuiltIn {
                            Button {
                                confirmRestore = true
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.uturn.backward")
                                        .foregroundColor(Color(red: 0.9, green: 0.5, blue: 0.2))
                                    Text("恢复内置数据")
                                        .foregroundColor(.white)
                                }
                            }
                        }
                    } header: {
                        Text("GAME DATA")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(red: 0.4, green: 0.7, blue: 0.9))
                    } footer: {
                        Text("配方、物品、建筑数据和物品图标可以在线更新，下载后重启 App 生效。")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .listRowBackground(Color(red: 0.12, green: 0.13, blue: 0.16))

                    // 数据管理
                    Section {
                        Button(role: .destructive) {
                            // 清除缓存
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("Clear Cache")
                            }
                        }
                    } header: {
                        Text("DATA")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.red.opacity(0.8))
                    }
                    .listRowBackground(Color(red: 0.12, green: 0.13, blue: 0.16))
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("SETTINGS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color(red: 0.08, green: 0.09, blue: 0.12), for: .navigationBar)
            .confirmationDialog("恢复成安装包自带的数据？", isPresented: $confirmRestore, titleVisibility: .visible) {
                Button("恢复内置数据", role: .destructive) { dataUpdater.restoreBuiltIn() }
            } message: {
                Text("下载的数据会被删除，重启 App 后生效。")
            }
        }
    }

    private var currentDataText: String {
        guard let manifest = DataPackStore.currentManifest else { return "内置" }
        return manifest.builtDateText + (DataPackStore.isUsingDownloadedData ? "（已更新）" : "（内置）")
    }

    /// 检查更新这一行：按状态显示按钮或进度
    @ViewBuilder
    private var dataUpdateRow: some View {
        let yellow = Color(red: 1.0, green: 0.8, blue: 0.0)
        switch dataUpdater.state {
        case .checking:
            HStack {
                ProgressView().tint(yellow)
                Text("正在检查…").foregroundColor(.white.opacity(0.6))
            }
        case .downloading(let done, let total):
            VStack(alignment: .leading, spacing: 6) {
                Text("正在下载 \(done)/\(total)").foregroundColor(.white.opacity(0.6))
                ProgressView(value: Double(done), total: Double(max(total, 1))).tint(yellow)
            }
        case .available(let remote):
            Button {
                Task { await dataUpdater.download() }
            } label: {
                HStack {
                    Image(systemName: "arrow.down.circle.fill").foregroundColor(yellow)
                    Text("下载新数据").foregroundColor(.white)
                    Spacer()
                    Text(remote.builtDateText)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                    Circle().fill(Color.red).frame(width: 8, height: 8)
                }
            }
        case .readyToRestart:
            HStack {
                Image(systemName: "checkmark.circle.fill").foregroundColor(Color(red: 0.4, green: 0.8, blue: 0.2))
                Text("已就绪，重启 App 后生效").foregroundColor(.white)
            }
        case .needsAppUpdate:
            HStack {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                Text("新数据需要更新 App 才能使用").foregroundColor(.white)
            }
        case .idle, .upToDate, .failed:
            Button {
                Task { await dataUpdater.check() }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath").foregroundColor(yellow)
                        Text("检查数据更新").foregroundColor(.white)
                        Spacer()
                        if dataUpdater.state == .upToDate {
                            Text("已是最新").font(.system(size: 12)).foregroundColor(.white.opacity(0.5))
                        }
                    }
                    if case .failed(let message) = dataUpdater.state {
                        Text(message).font(.system(size: 12)).foregroundColor(.red.opacity(0.8))
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
