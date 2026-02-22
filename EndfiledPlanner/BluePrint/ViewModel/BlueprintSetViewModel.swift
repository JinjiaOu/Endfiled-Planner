//
//  BlueprintSetViewModel.swift
//  EndfiledPlanner
//
//  Created by Jinjia Ou on 2/21/26.
//

import Foundation
import Combine

class BlueprintSetViewModel: ObservableObject {
    
    @Published var blueprintSets: [BlueprintSet] = []
    @Published var filteredSets: [BlueprintSet] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // 筛选条件
    @Published var authorSearch = ""
    @Published var selectedRegion: String?
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupSearchAndFilter()
    }
    
    // MARK: - 加载数据
    
    func loadBlueprintSets() {
        Task { @MainActor in
            isLoading = true
            errorMessage = nil
            
            do {
                let loadedSets = try await BlueprintSetService.shared.loadBlueprintSets()
                
                //  关键改动：随机打乱蓝图集顺序
                // 这样可以确保每次启动App时，不同作者的蓝图都有机会显示在前面
                // 实现公平展示，避免固定顺序导致排在前面的作者获得更多曝光
                self.blueprintSets = loadedSets.shuffled()
                self.filteredSets = loadedSets.shuffled()
                
                print(" 加载了 \(loadedSets.count) 个蓝图集（已随机排序）")
            } catch {
                self.errorMessage = "加载失败: \(error.localizedDescription)"
                print(" 加载蓝图集失败: \(error)")
            }
            
            isLoading = false
        }
    }
    
    func refreshBlueprintSets() {
        BlueprintSetService.shared.clearCache()
        loadBlueprintSets()
    }
    
    // MARK: - 搜索和筛选
    
    private func setupSearchAndFilter() {
        Publishers.CombineLatest($authorSearch, $selectedRegion)
            .debounce(for: 0.3, scheduler: RunLoop.main)
            .sink { [weak self] authorSearch, region in
                self?.applyFilters(authorSearch: authorSearch, region: region)
            }
            .store(in: &cancellables)
    }
    
    private func applyFilters(authorSearch: String, region: String?) {
        var result = blueprintSets
        
        // 作者搜索
        if !authorSearch.isEmpty {
            result = result.filter { set in
                set.author.localizedCaseInsensitiveContains(authorSearch)
            }
        }
        
        // 地图筛选
        if let region = region, region != "全部" {
            result = result.filter { $0.region == region }
        }
        
        filteredSets = result
    }
    
    // MARK: - 辅助方法
    
    var availableRegions: [String] {
        let regions = Set(blueprintSets.map { $0.region })
        return ["全部"] + regions.sorted()
    }
}
