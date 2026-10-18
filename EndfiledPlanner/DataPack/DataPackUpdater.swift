// Created by Jinjia Ou on 10/17/26.

import Combine
import CryptoKit
import Foundation

/// App 内一键更新数据（PLAN.md M5）：查远端清单 → 下载有变化的文件和图标 → 校验 → 放进 pending，下次启动生效。
/// 远端跟蓝图一样直接读仓库里的文件，Gitee 优先、GitHub 兜底
final class DataPackUpdater: ObservableObject {
    static let shared = DataPackUpdater()

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(DataPackManifest)
        /// 远端格式比 App 认识的新，要先升级 App
        case needsAppUpdate
        case downloading(done: Int, total: Int)
        /// 下载好了（或选了恢复内置），重启 App 后生效
        case readyToRestart
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    /// 首页齿轮上的红点
    var hasUpdate: Bool {
        if case .available = state { return true }
        return false
    }

    private static let mirrors = [
        "https://gitee.com/JinjiaOu/endfield--planner/raw/main/EndfiledPlanner/other/",
        "https://raw.githubusercontent.com/JinjiaOu/Endfiled-Planner/refs/heads/main/EndfiledPlanner/other/",
    ]

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    private init() {
        // 这次运行里已经下载好但还没启用的包
        if FileManager.default.fileExists(atPath: DataPackStore.pendingURL.appendingPathComponent(DataPackStore.manifestName).path)
            || FileManager.default.fileExists(atPath: DataPackStore.resetMarkerURL.path) {
            state = .readyToRestart
        }
    }

    /// 已下载待启用的清单（还没重启时，用它判断远端是不是又更新了）
    private var pendingManifest: DataPackManifest? {
        DataPackStore.readManifest(at: DataPackStore.pendingURL.appendingPathComponent(DataPackStore.manifestName))
    }

    // MARK: - 检查

    /// silent：启动时自动查，失败不显示错误
    func check(silent: Bool = false) async {
        switch state {
        case .checking, .downloading: return
        case .readyToRestart where silent: return
        default: break
        }
        let previous = state
        state = .checking
        guard let remote = await fetchManifest() else {
            state = silent ? previous : .failed("连不上更新服务器，请稍后再试")
            return
        }
        // 已经选了恢复内置时，下次启动用的是安装包数据，要跟安装包比
        let resetPending = FileManager.default.fileExists(atPath: DataPackStore.resetMarkerURL.path)
        let baseline = resetPending ? DataPackStore.bundledManifest : DataPackStore.currentManifest
        if remote.formatVersion > DataPackStore.supportedFormat {
            state = .needsAppUpdate
        } else if let pending = pendingManifest, !remote.isNewer(than: pending) {
            state = .readyToRestart
        } else if remote.isNewer(than: baseline) {
            state = .available(remote)
        } else {
            state = resetPending ? .readyToRestart : .upToDate
        }
    }

    private func fetchManifest() async -> DataPackManifest? {
        for mirror in Self.mirrors {
            guard let url = URL(string: mirror + DataPackStore.manifestName),
                  let data = try? await fetch(url),
                  let manifest = try? JSONDecoder().decode(DataPackManifest.self, from: data)
            else { continue }
            return manifest
        }
        return nil
    }

    private func fetch(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }

    // MARK: - 下载

    private struct Job {
        let remotePath: String
        let destination: URL
        let entry: DataPackManifest.Entry
        /// 本地已有同样内容的副本，直接复制不下载
        let localCopy: URL?
    }

    func download() async {
        guard case .available(let remote) = state else { return }
        let fm = FileManager.default
        let staging = DataPackStore.stagingURL
        try? fm.removeItem(at: staging)

        var jobs: [Job] = []
        for (name, entry) in remote.files.sorted(by: { $0.key < $1.key }) {
            jobs.append(Job(remotePath: name, destination: staging.appendingPathComponent(name), entry: entry,
                            localCopy: DataPackStore.localCopy(ofFile: name, matching: entry)))
        }
        let icons = DataPackStore.iconsURL(in: staging)
        // 安装包里已有同样的图就不下载，显示时自然会用安装包的
        for (itemID, entry) in remote.icons.sorted(by: { $0.key < $1.key }) where !DataPackStore.bundleHasIcon(itemID, matching: entry) {
            jobs.append(Job(remotePath: "ItemIcons.xcassets/\(itemID).imageset/icon.png",
                            destination: icons.appendingPathComponent("\(itemID).png"), entry: entry,
                            localCopy: DataPackStore.localIcon(itemID, matching: entry)))
        }

        do {
            try fm.createDirectory(at: icons, withIntermediateDirectories: true)
            for (index, job) in jobs.enumerated() {
                state = .downloading(done: index, total: jobs.count)
                let data: Data
                if let local = job.localCopy, let copy = try? Data(contentsOf: local), Self.matches(copy, job.entry) {
                    data = copy
                } else {
                    data = try await downloadVerified(job.remotePath, job.entry)
                }
                try data.write(to: job.destination, options: .atomic)
            }
            // 数据文件至少要是合法 JSON，结构不对时 DataPackStore 读的时候还会再退回安装包
            for name in remote.files.keys {
                _ = try JSONSerialization.jsonObject(with: Data(contentsOf: staging.appendingPathComponent(name)))
            }
            // 清单最后写：pending 里有清单才算完整的包
            try JSONEncoder().encode(remote).write(to: staging.appendingPathComponent(DataPackStore.manifestName))
            try? fm.removeItem(at: DataPackStore.pendingURL)
            try? fm.removeItem(at: DataPackStore.resetMarkerURL)
            try fm.moveItem(at: staging, to: DataPackStore.pendingURL)
            state = .readyToRestart
        } catch {
            try? fm.removeItem(at: staging)
            print("数据包下载失败:", error)
            state = .failed("下载失败，当前数据没有改动，可以再试一次")
        }
    }

    /// 依次试各个镜像，内容校验通过才算数
    private func downloadVerified(_ path: String, _ entry: DataPackManifest.Entry) async throws -> Data {
        for mirror in Self.mirrors {
            guard let url = URL(string: mirror + path),
                  let data = try? await fetch(url), Self.matches(data, entry) else { continue }
            return data
        }
        throw URLError(.cannotDecodeContentData)
    }

    private static func matches(_ data: Data, _ entry: DataPackManifest.Entry) -> Bool {
        guard data.count == entry.size else { return false }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == entry.sha256
    }

    // MARK: - 恢复内置

    /// 现在有在用或待启用的下载数据时才有意义
    var canRestoreBuiltIn: Bool {
        if FileManager.default.fileExists(atPath: DataPackStore.resetMarkerURL.path) { return false }
        return DataPackStore.isUsingDownloadedData || pendingManifest != nil
    }

    func restoreBuiltIn() {
        let fm = FileManager.default
        try? fm.removeItem(at: DataPackStore.pendingURL)
        if DataPackStore.isUsingDownloadedData {
            try? fm.createDirectory(at: DataPackStore.rootURL, withIntermediateDirectories: true)
            fm.createFile(atPath: DataPackStore.resetMarkerURL.path, contents: Data())
            state = .readyToRestart
        } else {
            // 只是撤销还没启用的下载，当前本来就在用内置数据
            state = .idle
        }
    }
}
