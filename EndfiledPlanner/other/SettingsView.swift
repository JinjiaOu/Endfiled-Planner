//
//  SettingsView.swift
//  EndfiledPlanner
//
//  Created by Jinjia Ou on 2/14/26.
//

import SwiftUI

struct SettingsView: View {

    var isPresentedModally = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    private static let repositoryURL = URL(string: "https://github.com/JinjiaOu/Endfiled-Planner")!
    
    @AppStorage("darkMode") private var darkMode = false
    @ObservedObject private var dataUpdater = DataPackUpdater.shared
    @State private var confirmRestore = false
    @State private var showReportOptions = false
    @State private var showFeedback = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppTopographicBackground()
                
                List {
                    
                    // 关于
                    Section {
                        HStack {
                            Text("VERSION")
                                .foregroundColor(AppColors.primaryText.opacity(0.6))
                            Spacer()
                            Text("1.0.0")
                                .font(.system(size: 14, design: .monospaced))
                                .foregroundColor(Color(red: 1.0, green: 0.8, blue: 0.0))
                        }
                        
                        Button {
                            openURL(Self.repositoryURL)
                        } label: {
                            HStack {
                                Image(systemName: "link")
                                    .foregroundColor(Color(red: 1.0, green: 0.8, blue: 0.0))
                                Text("GitHub Repository")
                                    .foregroundColor(AppColors.primaryText)
                            }
                        }
                        
                        Button {
                            showReportOptions = true
                        } label: {
                            HStack {
                                Image(systemName: "exclamationmark.bubble")
                                    .foregroundColor(Color(red: 0.9, green: 0.5, blue: 0.2))
                                Text("Report Issue")
                                    .foregroundColor(AppColors.primaryText)
                            }
                        }

                        // 语言跟随系统；这里跳到系统设置里本 App 的页面，可以单独给 App 选语言
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        } label: {
                            HStack {
                                Image(systemName: "globe")
                                    .foregroundColor(Color(red: 1.0, green: 0.8, blue: 0.0))
                                Text(String(localized: "语言"))
                                    .foregroundColor(AppColors.primaryText)
                                Spacer()
                                Text(verbatim: currentLanguageName)
                                    .font(.system(size: 13))
                                    .foregroundColor(AppColors.primaryText.opacity(0.5))
                                Image(systemName: "arrow.up.forward.app")
                                    .font(.system(size: 12))
                                    .foregroundColor(AppColors.primaryText.opacity(0.4))
                            }
                        }
                        .accessibilityHint(String(localized: "在系统设置里切换 App 语言"))
                    } header: {
                        Text("ABOUT")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(AppColors.primaryText.opacity(0.6))
                    }
                    .listRowBackground(AppColors.surface)
                    
                    // 游戏数据（配方/物品/建筑/图标）在线更新
                    Section {
                        HStack {
                            Text(String(localized: "数据版本"))
                                .foregroundColor(AppColors.primaryText.opacity(0.6))
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
                                    Text(String(localized: "恢复内置数据"))
                                        .foregroundColor(AppColors.primaryText)
                                }
                            }
                        }
                    } header: {
                        Text("GAME DATA")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(red: 0.4, green: 0.7, blue: 0.9))
                    } footer: {
                        Text(String(localized: "配方、物品、建筑数据和物品图标可以在线更新，下载后重启 App 生效。"))
                            .font(.system(size: 11))
                            .foregroundColor(AppColors.primaryText.opacity(0.4))
                    }
                    .listRowBackground(AppColors.surface)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("SETTINGS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isPresentedModally {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "完成")) { dismiss() }
                    }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(AppColors.background, for: .navigationBar)
            // 反馈：普通玩家用 App 内反馈（存 CloudKit，不用邮箱和账号），会用 GitHub 的走 Issues（正文预填版本信息）
            .confirmationDialog(String(localized: "反馈问题"), isPresented: $showReportOptions, titleVisibility: .visible) {
                Button(String(localized: "在 App 内反馈")) { showFeedback = true }
                Button("GitHub Issues") { openURL(FeedbackInfo.githubIssueURL) }
                Button(String(localized: "取消"), role: .cancel) {}
            } message: {
                Text(String(localized: "App 内反馈不用注册账号，直接发送；GitHub Issues 需要 GitHub 账号。"))
            }
            .sheet(isPresented: $showFeedback) {
                NavigationStack { FeedbackView() }
            }
            .confirmationDialog(String(localized: "恢复成安装包自带的数据？"), isPresented: $confirmRestore, titleVisibility: .visible) {
                Button(String(localized: "恢复内置数据"), role: .destructive) { dataUpdater.restoreBuiltIn() }
            } message: {
                Text(String(localized: "下载的数据会被删除，重启 App 后生效。"))
            }
        }
    }

    /// 当前界面语言的名字（用该语言自己的写法，如"简体中文""English"）
    private var currentLanguageName: String {
        let code = Bundle.main.preferredLocalizations.first ?? "zh-Hans"
        return Locale(identifier: code).localizedString(forIdentifier: code) ?? code
    }

    private var currentDataText: String {
        guard let manifest = DataPackStore.currentManifest else { return String(localized: "内置") }
        return manifest.builtDateText + (DataPackStore.isUsingDownloadedData ? String(localized: "（已更新）") : String(localized: "（内置）"))
    }

    /// 检查更新这一行：按状态显示按钮或进度
    @ViewBuilder
    private var dataUpdateRow: some View {
        let yellow = Color(red: 1.0, green: 0.8, blue: 0.0)
        switch dataUpdater.state {
        case .checking:
            HStack {
                ProgressView().tint(yellow)
                Text(String(localized: "正在检查…")).foregroundColor(AppColors.primaryText.opacity(0.6))
            }
        case .downloading(let done, let total):
            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "正在下载 \(done)/\(total)")).foregroundColor(AppColors.primaryText.opacity(0.6))
                ProgressView(value: Double(done), total: Double(max(total, 1))).tint(yellow)
            }
        case .available(let remote):
            Button {
                Task { await dataUpdater.download() }
            } label: {
                HStack {
                    Image(systemName: "arrow.down.circle.fill").foregroundColor(yellow)
                    Text(String(localized: "下载新数据")).foregroundColor(AppColors.primaryText)
                    Spacer()
                    Text(remote.builtDateText)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(AppColors.primaryText.opacity(0.5))
                    Circle().fill(Color.red).frame(width: 8, height: 8)
                }
            }
        case .readyToRestart:
            HStack {
                Image(systemName: "checkmark.circle.fill").foregroundColor(Color(red: 0.4, green: 0.8, blue: 0.2))
                Text(String(localized: "已就绪，重启 App 后生效")).foregroundColor(AppColors.primaryText)
            }
        case .needsAppUpdate:
            HStack {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                Text(String(localized: "新数据需要更新 App 才能使用")).foregroundColor(AppColors.primaryText)
            }
        case .idle, .upToDate, .failed:
            Button {
                Task { await dataUpdater.check() }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath").foregroundColor(yellow)
                        Text(String(localized: "检查数据更新")).foregroundColor(AppColors.primaryText)
                        Spacer()
                        if dataUpdater.state == .upToDate {
                            Text(String(localized: "已是最新")).font(.system(size: 12)).foregroundColor(AppColors.primaryText.opacity(0.5))
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
