//
//  BlueprintSetService.swift
//  EndfiledPlanner
//
//  Created by Jinjia Ou on 2/21/26.
//

import Foundation

class BlueprintSetService {
    
    static let shared = BlueprintSetService()
    
    // Gitee URL
    private let giteeURL = "https://gitee.com/JinjiaOu/endfield--planner/raw/main/EndfiledPlanner/BluePrint/blueprints.json"
    
    // GitHub URL
    private let githubURL = "https://raw.githubusercontent.com/JinjiaOu/Endfiled-Planner/refs/heads/main/EndfiledPlanner/BluePrint/blueprints.json"
    
    // 缓存
    private let cacheKey = "cached_blueprint_sets"
    private let cacheTimestampKey = "cache_timestamp"
    private let cacheValidDuration: TimeInterval = 3600
    
    private init() {}
    
    // MARK: - 加载蓝图集
    
    func loadBlueprintSets() async throws -> [BlueprintSet] {
        
        // 1. 缓存
        if let cached = loadFromCache() {
            print("✅ 从缓存加载蓝图集")
            return cached
        }
        
        // 2. Gitee
        do {
            let sets = try await fetchFromURL(giteeURL)
            print("✅ 从 Gitee 加载蓝图集")
            saveToCache(sets)
            return sets
        } catch {
            print("⚠️ Gitee 加载失败: \(error.localizedDescription)")
        }
        
        // 3. GitHub
        do {
            let sets = try await fetchFromURL(githubURL)
            print("✅ 从 GitHub 加载蓝图集")
            saveToCache(sets)
            return sets
        } catch {
            print("❌ GitHub 加载失败: \(error.localizedDescription)")
        }
        
        // 4. Bundle
        if let bundled = loadFromBundle() {
            print("✅ 从本地 Bundle 加载蓝图集")
            return bundled
        }
        
        throw BlueprintError.loadFailed
    }
    
    // MARK: - 网络请求
    
    private func fetchFromURL(_ urlString: String) async throws -> [BlueprintSet] {
        guard let url = URL(string: urlString) else {
            throw BlueprintError.invalidURL
        }
        
        let (data, httpResponse) = try await URLSession.shared.data(from: url)
        
        guard let response = httpResponse as? HTTPURLResponse,
              response.statusCode == 200 else {
            throw BlueprintError.networkError
        }
        
        let decoder = JSONDecoder()
        let setsResponse = try decoder.decode(BlueprintSetsResponse.self, from: data)
        
        return setsResponse.blueprintSets
    }
    
    // MARK: - 缓存
    
    private func loadFromCache() -> [BlueprintSet]? {
        if let timestamp = UserDefaults.standard.object(forKey: cacheTimestampKey) as? Date {
            if Date().timeIntervalSince(timestamp) > cacheValidDuration {
                print("⚠️ 缓存已过期")
                return nil
            }
        } else {
            return nil
        }
        
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else {
            return nil
        }
        
        let decoder = JSONDecoder()
        return try? decoder.decode([BlueprintSet].self, from: data)
    }
    
    private func saveToCache(_ sets: [BlueprintSet]) {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(sets) {
            UserDefaults.standard.set(data, forKey: cacheKey)
            UserDefaults.standard.set(Date(), forKey: cacheTimestampKey)
            print("💾 蓝图集已缓存")
        }
    }
    
    func clearCache() {
        UserDefaults.standard.removeObject(forKey: cacheKey)
        UserDefaults.standard.removeObject(forKey: cacheTimestampKey)
        print("🗑️ 缓存已清除")
    }
    
    // MARK: - Bundle
    
    private func loadFromBundle() -> [BlueprintSet]? {
        guard let url = Bundle.main.url(forResource: "blueprints", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        
        let decoder = JSONDecoder()
        let setsResponse = try? decoder.decode(BlueprintSetsResponse.self, from: data)
        return setsResponse?.blueprintSets
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
