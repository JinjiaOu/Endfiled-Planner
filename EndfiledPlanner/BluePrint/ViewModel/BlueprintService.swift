//
//  BlueprintService.swift
//  EndfiledPlanner
//
//  Created by Jinjia Ou on 2/21/26.
//

import Foundation

class BlueprintService {
    
    static let shared = BlueprintService()
    
    // Gitee URL (国内访问更快)
    private let giteeURL = "https://gitee.com/JinjiaOu/endfield--planner/raw/main/blueprints.json"
    
    // GitHub URL (备用)
    private let githubURL = "https://raw.githubusercontent.com/JinjiaOu/Endfiled-Planner/main/blueprints.json"
    
    // 缓存键
    private let cacheKey = "cached_blueprints"
    private let cacheTimestampKey = "cache_timestamp"
    private let cacheValidDuration: TimeInterval = 3600 // 1小时
    
    private init() {}
    
    // MARK: - 加载蓝图数据
    
    func loadBlueprints() async throws -> [Blueprint] {
        
        // 1. 尝试从缓存加载
        if let cached = loadFromCache() {
            print("✅ 从缓存加载蓝图数据")
            return cached
        }
        
        // 2. 尝试从 Gitee 加载
        do {
            let blueprints = try await fetchFromURL(giteeURL)
            print("✅ 从 Gitee 加载蓝图数据")
            saveToCache(blueprints)
            return blueprints
        } catch {
            print("⚠️ Gitee 加载失败: \(error.localizedDescription)")
        }
        
        // 3. 回退到 GitHub
        do {
            let blueprints = try await fetchFromURL(githubURL)
            print("✅ 从 GitHub 加载蓝图数据")
            saveToCache(blueprints)
            return blueprints
        } catch {
            print("❌ GitHub 加载失败: \(error.localizedDescription)")
        }
        
        // 4. 尝试从 Bundle 加载本地备份
        if let bundled = loadFromBundle() {
            print("✅ 从本地 Bundle 加载蓝图数据")
            return bundled
        }
        
        throw BlueprintError.loadFailed
    }
    
    // MARK: - 网络请求
    
    private func fetchFromURL(_ urlString: String) async throws -> [Blueprint] {
        guard let url = URL(string: urlString) else {
            throw BlueprintError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw BlueprintError.networkError
        }
        
        let decoder = JSONDecoder()
        let response = try decoder.decode(BlueprintResponse.self, from: data)
        
        return response.blueprints
    }
    
    // MARK: - 缓存管理
    
    private func loadFromCache() -> [Blueprint]? {
        
        // 检查缓存是否过期
        if let timestamp = UserDefaults.standard.object(forKey: cacheTimestampKey) as? Date {
            if Date().timeIntervalSince(timestamp) > cacheValidDuration {
                print("⚠️ 缓存已过期")
                return nil
            }
        } else {
            return nil
        }
        
        // 加载缓存数据
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else {
            return nil
        }
        
        let decoder = JSONDecoder()
        return try? decoder.decode([Blueprint].self, from: data)
    }
    
    private func saveToCache(_ blueprints: [Blueprint]) {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(blueprints) {
            UserDefaults.standard.set(data, forKey: cacheKey)
            UserDefaults.standard.set(Date(), forKey: cacheTimestampKey)
            print("💾 蓝图数据已缓存")
        }
    }
    
    func clearCache() {
        UserDefaults.standard.removeObject(forKey: cacheKey)
        UserDefaults.standard.removeObject(forKey: cacheTimestampKey)
        print("🗑️ 缓存已清除")
    }
    
    // MARK: - Bundle 加载
    
    private func loadFromBundle() -> [Blueprint]? {
        guard let url = Bundle.main.url(forResource: "blueprints", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        
        let decoder = JSONDecoder()
        let response = try? decoder.decode(BlueprintResponse.self, from: data)
        return response?.blueprints
    }
}

// MARK: - 错误类型

enum BlueprintError: Error, LocalizedError {
    case invalidURL
    case networkError
    case loadFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的 URL"
        case .networkError:
            return "网络请求失败"
        case .loadFailed:
            return "加载蓝图数据失败"
        }
    }
}
