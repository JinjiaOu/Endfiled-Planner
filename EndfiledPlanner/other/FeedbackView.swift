// Created by Jinjia Ou on 10/21/26.

import CloudKit
import PhotosUI
import SwiftUI
import UIKit

/// App 内反馈：不用邮箱、不用注册账号，写完直接存进 CloudKit 公共库（只要手机登录了 iCloud）。
/// 开发者在 CloudKit 控制台的 Feedback 记录类型里查看。
struct FeedbackView: View {
    @Environment(\.dismiss) private var dismiss

    enum Category: String, CaseIterable, Identifiable {
        case recipe = "配方查询", blueprint = "社区蓝图", factory = "基建规划", calculator = "产量计算",
             data = "游戏数据", other = "其他"
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .recipe: return String(localized: "配方查询")
            case .blueprint: return String(localized: "社区蓝图")
            case .factory: return String(localized: "基建规划")
            case .calculator: return String(localized: "产量计算")
            case .data: return String(localized: "游戏数据")
            case .other: return String(localized: "其他")
            }
        }
    }

    @State private var category: Category = .factory
    @State private var message = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var screenshot: UIImage?
    @State private var isSending = false
    @State private var errorText: String?
    @State private var sent = false
    @State private var remainingToday = FeedbackInfo.remainingToday
    @FocusState private var messageFocused: Bool

    private var canSend: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending && remainingToday > 0
    }

    var body: some View {
        Form {
            Section {
                Picker(String(localized: "问题类型"), selection: $category) {
                    ForEach(Category.allCases) { Text(verbatim: $0.displayName).tag($0) }
                }
            }
            .listRowBackground(AppColors.surface)

            Section {
                TextEditor(text: $message)
                    .frame(minHeight: 160)
                    .focused($messageFocused)
                    .overlay(alignment: .topLeading) {
                        if message.isEmpty {
                            Text(String(localized: "遇到了什么问题？怎么操作会出现？也可以写建议。"))
                                .foregroundStyle(AppColors.tertiaryText)
                                .padding(.top, 8).padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
            } header: {
                Text(String(localized: "描述"))
            }
            .listRowBackground(AppColors.surface)

            Section {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(screenshot == nil ? String(localized: "添加截图（可选）") : String(localized: "换一张截图"), systemImage: "photo")
                }
                if let screenshot {
                    HStack {
                        Image(uiImage: screenshot).resizable().scaledToFit()
                            .frame(maxHeight: 160)
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.control))
                        Spacer()
                        Button(role: .destructive) {
                            self.screenshot = nil
                            photoItem = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(AppColors.secondaryText)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "移除截图"))
                    }
                }
            }
            .listRowBackground(AppColors.surface)

            Section {
                ForEach(FeedbackInfo.lines, id: \.0) { title, value in
                    LabeledContent(title, value: value)
                }
            } header: {
                Text(String(localized: "会一起发送"))
            } footer: {
                Text(String(localized: "只发送上面这些和你填写的内容，不包含账号或个人信息。需要手机登录 iCloud。")
                     + String(localized: "每天最多发 \(FeedbackInfo.dailyLimit) 条，今天还能发 \(remainingToday) 条。"))
            }
            .listRowBackground(AppColors.surface)

            if remainingToday == 0 {
                Section {
                    AppInlineNotice(title: String(localized: "今天的反馈次数用完了"),
                                    message: String(localized: "明天再来，或者改用 GitHub Issues 反馈。"), tone: .warning)
                }
                .listRowBackground(AppColors.surface)
            }

            if let errorText {
                Section {
                    AppInlineNotice(title: String(localized: "没发出去"), message: errorText, tone: .error)
                }
                .listRowBackground(AppColors.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.background)
        .navigationTitle(String(localized: "反馈问题"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "取消")) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                if isSending {
                    ProgressView()
                } else {
                    Button(String(localized: "发送")) { Task { await send() } }
                        .disabled(!canSend)
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(String(localized: "完成")) { messageFocused = false }
            }
        }
        .onChange(of: photoItem) { _, item in
            Task { await loadScreenshot(item) }
        }
        .alert(String(localized: "已发送，谢谢反馈！"), isPresented: $sent) {
            Button(String(localized: "好")) { dismiss() }
        }
        .interactiveDismissDisabled(isSending)
    }

    private func loadScreenshot(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        screenshot = image
    }

    private func send() async {
        messageFocused = false
        errorText = nil
        isSending = true
        defer { isSending = false }
        do {
            try await FeedbackInfo.submit(category: category.rawValue, message: message, screenshot: screenshot)
            FeedbackInfo.recordSent()
            remainingToday = FeedbackInfo.remainingToday
            sent = true
        } catch {
            errorText = FeedbackInfo.describe(error)
        }
    }
}

/// 反馈附带的版本信息，以及提交到 CloudKit 的实现（GitHub Issues 预填正文也用这里的版本信息）
enum FeedbackInfo {
    static let containerID = "iCloud.com.Owen.EndfiledPlanner"
    static let recordType = "Feedback"

    // MARK: 每天限次（用户 2026-10-21 定 5 次）：只在本机记，防手滑连发和刷屏；按本地日期换天
    static let dailyLimit = 5
    private static let countKey = "feedbackSentCount"
    private static let dayKey = "feedbackSentDay"

    private static var today: String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: .now)
    }

    static var remainingToday: Int {
        let defaults = UserDefaults.standard
        let used = defaults.string(forKey: dayKey) == today ? defaults.integer(forKey: countKey) : 0
        return max(0, dailyLimit - used)
    }

    static func recordSent() {
        let defaults = UserDefaults.standard
        let used = defaults.string(forKey: dayKey) == today ? defaults.integer(forKey: countKey) : 0
        defaults.set(today, forKey: dayKey)
        defaults.set(used + 1, forKey: countKey)
    }

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    static var dataVersion: String {
        guard let manifest = DataPackStore.currentManifest else { return "内置" }
        return manifest.builtDateText + (DataPackStore.isUsingDownloadedData ? "（已更新）" : "（内置）")
    }

    static var displayDataVersion: String {
        guard let manifest = DataPackStore.currentManifest else { return String(localized: "内置") }
        return manifest.builtDateText + (DataPackStore.isUsingDownloadedData ? String(localized: "（已更新）") : String(localized: "（内置）"))
    }

    static var systemVersion: String { "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)" }

    /// 机型标识（如 iPhone16,1），不含设备名等个人信息
    static var deviceModel: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    static var lines: [(String, String)] {
        [(String(localized: "App 版本"), appVersion), (String(localized: "数据版本"), displayDataVersion), (String(localized: "系统"), systemVersion), (String(localized: "机型"), deviceModel)]
    }

    /// GitHub 新建 Issue 页面，正文预填版本信息
    static var githubIssueURL: URL {
        let body = String(localized: """
        **问题描述**


        **怎么操作会出现**


        ---
        \(lines.map { "- \($0.0)：\($0.1)" }.joined(separator: "\n"))
        """)
        var components = URLComponents(string: "https://github.com/JinjiaOu/Endfiled-Planner/issues/new")!
        components.queryItems = [URLQueryItem(name: "body", value: body)]
        return components.url!
    }

    static func submit(category: String, message: String, screenshot: UIImage?) async throws {
        guard remainingToday > 0 else { throw FeedbackError.dailyLimit }
        let container = CKContainer(identifier: containerID)
        guard try await container.accountStatus() == .available else { throw FeedbackError.noICloud }

        let record = CKRecord(recordType: recordType)
        record["category"] = category
        record["message"] = message.trimmingCharacters(in: .whitespacesAndNewlines)
        record["appVersion"] = appVersion
        record["dataVersion"] = dataVersion
        record["systemVersion"] = systemVersion
        record["deviceModel"] = deviceModel

        var tempURL: URL?
        if let screenshot, let data = resized(screenshot, maxSide: 1600).jpegData(compressionQuality: 0.7) {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("feedback-\(UUID().uuidString).jpg")
            try data.write(to: url)
            record["screenshot"] = CKAsset(fileURL: url)
            tempURL = url
        }
        defer { if let tempURL { try? FileManager.default.removeItem(at: tempURL) } }

        _ = try await container.publicCloudDatabase.save(record)
    }

    static func describe(_ error: Error) -> String {
        if let error = error as? FeedbackError { return error.message }
        if let ck = error as? CKError {
            switch ck.code {
            case .notAuthenticated: return FeedbackError.noICloud.message
            case .networkUnavailable, .networkFailure: return String(localized: "网络不太好，稍后再试。")
            case .quotaExceeded, .requestRateLimited, .serviceUnavailable, .zoneBusy:
                return String(localized: "服务器忙，稍后再试。")
            default: break
            }
        }
        return String(localized: "发送失败（\(error.localizedDescription)）。也可以改用 GitHub Issues 反馈。")
    }

    private static func resized(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxSide else { return image }
        let scale = maxSide / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
}

enum FeedbackError: Error {
    case noICloud
    case dailyLimit
    var message: String {
        switch self {
        case .noICloud: return String(localized: "手机没有登录 iCloud，发不了。可以在系统设置里登录 iCloud，或者改用 GitHub Issues 反馈。")
        case .dailyLimit: return String(localized: "今天已经发了 \(FeedbackInfo.dailyLimit) 条，明天再来，或者改用 GitHub Issues 反馈。")
        }
    }
}

#Preview {
    NavigationStack { FeedbackView() }
}
