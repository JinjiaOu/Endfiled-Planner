// Created by Jinjia Ou on 10/17/26.

import Foundation
import UIKit

/// datapack_manifest.json（Tools/gen_manifest.py 生成）：可下发的数据文件和物品图标，每项带 sha256 和大小
struct DataPackManifest: Codable, Equatable {
    struct Entry: Codable, Equatable {
        let sha256: String
        let size: Int
    }

    let formatVersion: Int
    /// 内容指纹，文件或图标有变化才会变
    let dataVersion: String
    /// 生成时间（ISO 8601，UTC），比新旧用这个
    let builtAt: String
    let sourceCommit: String?
    let files: [String: Entry]
    /// 物品 id → 图标（远端路径 ItemIcons.xcassets/<id>.imageset/icon.png）
    let icons: [String: Entry]

    func isNewer(than other: DataPackManifest?) -> Bool {
        guard let other else { return true }
        return builtAt > other.builtAt
    }

    /// 给设置页显示的日期
    var builtDateText: String {
        guard let date = ISO8601DateFormatter().date(from: builtAt) else { return builtAt }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

/// App 内更新的数据从哪读（PLAN.md M5）：
/// - 下载的数据包存在 Application Support/DataPack/active，比安装包自带的新才用，否则用安装包里的
/// - 下载好的新包先放 pending，下次启动才换成 active，所以一次运行里读到的数据始终是同一版
/// - "恢复内置数据"写一个 reset 标记，下次启动删掉 active
/// - 下载包里某个文件读不出来时，单个文件退回安装包自带的
enum DataPackStore {
    /// App 认识的最高数据包格式版本，跟 Tools/gen_manifest.py 的 FORMAT_VERSION 对应
    static let supportedFormat = 1
    static let manifestName = "datapack_manifest.json"

    static let rootURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("DataPack", isDirectory: true)
    }()
    static var activeURL: URL { rootURL.appendingPathComponent("active", isDirectory: true) }
    static var pendingURL: URL { rootURL.appendingPathComponent("pending", isDirectory: true) }
    static var stagingURL: URL { rootURL.appendingPathComponent("staging", isDirectory: true) }
    static var resetMarkerURL: URL { rootURL.appendingPathComponent("reset") }
    static func iconsURL(in dir: URL) -> URL { dir.appendingPathComponent("icons", isDirectory: true) }

    static let bundledManifest: DataPackManifest? = {
        guard let url = Bundle.main.url(forResource: "datapack_manifest", withExtension: "json") else { return nil }
        return readManifest(at: url)
    }()

    /// 这次运行用的下载包清单（没有、太新或不比安装包新时为 nil）。第一次访问时顺带处理 reset 和 pending
    static let activeManifest: DataPackManifest? = {
        applyPendingChanges()
        guard let manifest = readManifest(at: activeURL.appendingPathComponent(manifestName)),
              manifest.formatVersion <= supportedFormat,
              manifest.isNewer(than: bundledManifest)
        else { return nil }
        return manifest
    }()

    /// 当前生效的数据版本
    static var currentManifest: DataPackManifest? { activeManifest ?? bundledManifest }
    static var isUsingDownloadedData: Bool { activeManifest != nil }

    /// 启动时调用一次，保证 pending/reset 在任何数据被读之前处理掉
    static func prepare() {
        _ = activeManifest
    }

    static func readManifest(at url: URL) -> DataPackManifest? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(DataPackManifest.self, from: data)
    }

    private static func applyPendingChanges() {
        let fm = FileManager.default
        if fm.fileExists(atPath: resetMarkerURL.path) {
            try? fm.removeItem(at: activeURL)
            try? fm.removeItem(at: resetMarkerURL)
            print("数据包：已恢复内置数据")
        }
        if fm.fileExists(atPath: pendingURL.appendingPathComponent(manifestName).path) {
            try? fm.removeItem(at: activeURL)
            do {
                try fm.moveItem(at: pendingURL, to: activeURL)
                print("数据包：已启用新下载的数据")
            } catch {
                print("数据包：启用新数据失败", error)
            }
        }
        try? fm.removeItem(at: stagingURL)
    }

    // MARK: - 读数据文件

    /// 依次给出候选文件：下载包里的（如果在用）→ 安装包里的
    private static func candidateURLs(_ name: String, _ ext: String) -> [URL] {
        var urls: [URL] = []
        if activeManifest?.files["\(name).\(ext)"] != nil {
            urls.append(activeURL.appendingPathComponent("\(name).\(ext)"))
        }
        if let bundled = Bundle.main.url(forResource: name, withExtension: ext) {
            urls.append(bundled)
        }
        return urls
    }

    /// 按候选顺序解码，前一个读不出来就退回下一个；全部失败返回 nil
    static func decode<T: Decodable>(_ type: T.Type, resource name: String, withExtension ext: String = "json") -> T? {
        for url in candidateURLs(name, ext) {
            do {
                return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
            } catch {
                print("数据包：\(url.lastPathComponent) 读取失败（\(url.path)）", error)
            }
        }
        return nil
    }

    // MARK: - 图标

    private static let iconCache = NSCache<NSString, UIImage>()

    /// 下载包里实际存了文件的图标（只下安装包里没有或有变化的那些），启动时列一次目录
    private static let downloadedIconIDs: Set<String> = {
        guard activeManifest != nil,
              let names = try? FileManager.default.contentsOfDirectory(atPath: iconsURL(in: activeURL).path)
        else { return [] }
        return Set(names.filter { $0.hasSuffix(".png") }.map { String($0.dropLast(4)) })
    }()

    /// 下载包里的物品图标；没有就返回 nil，调用方再去找安装包里的
    static func icon(for itemID: String) -> UIImage? {
        guard downloadedIconIDs.contains(itemID) else { return nil }
        if let cached = iconCache.object(forKey: itemID as NSString) { return cached }
        let url = iconsURL(in: activeURL).appendingPathComponent("\(itemID).png")
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        iconCache.setObject(image, forKey: itemID as NSString)
        return image
    }

    /// 某个文件/图标在当前生效的数据里能直接复用的本地副本（内容跟清单里的 sha256 一样才算）
    static func localCopy(ofFile name: String, matching entry: DataPackManifest.Entry) -> URL? {
        if let active = activeManifest, active.files[name] == entry {
            let url = activeURL.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        if bundledManifest?.files[name] == entry {
            let parts = name.split(separator: ".", maxSplits: 1).map(String.init)
            return Bundle.main.url(forResource: parts[0], withExtension: parts.count > 1 ? parts[1] : nil)
        }
        return nil
    }

    static func localIcon(_ itemID: String, matching entry: DataPackManifest.Entry) -> URL? {
        guard activeManifest?.icons[itemID] == entry, downloadedIconIDs.contains(itemID) else { return nil }
        return iconsURL(in: activeURL).appendingPathComponent("\(itemID).png")
    }

    static func bundleHasIcon(_ itemID: String, matching entry: DataPackManifest.Entry) -> Bool {
        bundledManifest?.icons[itemID] == entry
    }
}
