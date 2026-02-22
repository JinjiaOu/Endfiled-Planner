//
//  BlueprintViewModel.swift
//  EndfiledPlanner
//
//  Created by Jinjia Ou on 2/21/26.
//

import Foundation
import Combine

class BlueprintViewModel: ObservableObject {
    
    @Published var blueprints: [Blueprint] = []
    @Published var filteredBlueprints: [Blueprint] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    @Published var searchText = ""
    @Published var selectedRegion: String?
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupSearchAndFilter()
    }
    
    // MARK: - 加载数据
    
    func loadBlueprints() {
        Task { @MainActor in
            isLoading = true
            errorMessage = nil
            
            do {
                let loadedBlueprints = try await BlueprintService.shared.loadBlueprints()
                self.blueprints = loadedBlueprints
                self.filteredBlueprints = loadedBlueprints
                print("📦 加载了 \(loadedBlueprints.count) 个蓝图")
            } catch {
                self.errorMessage = "加载失败: \(error.localizedDescription)"
                print("❌ 加载蓝图失败: \(error)")
            }
            
            isLoading = false
        }
    }
    
    func refreshBlueprints() {
        BlueprintService.shared.clearCache()
        loadBlueprints()
    }
    
    // MARK: - 搜索和筛选
    
    private func setupSearchAndFilter() {
        // 监听搜索文本和地区的变化
        Publishers.CombineLatest($searchText, $selectedRegion)
            .debounce(for: 0.3, scheduler: RunLoop.main)
            .sink { [weak self] searchText, region in
                self?.applyFilters(searchText: searchText, region: region)
            }
            .store(in: &cancellables)
    }
    
    private func applyFilters(searchText: String, region: String?) {
        var result = blueprints
        
        // 搜索过滤
        if !searchText.isEmpty {
            result = result.filter { blueprint in
                blueprint.name.localizedCaseInsensitiveContains(searchText) ||
                blueprint.author.localizedCaseInsensitiveContains(searchText) ||
                blueprint.notes.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // 地区过滤
        if let region = region, region != "全部" {
            result = result.filter { $0.region == region }
        }
        
        filteredBlueprints = result
    }
    
    // MARK: - 辅助方法
    
    var availableRegions: [String] {
        let regions = Set(blueprints.map { $0.region })
        return ["全部"] + regions.sorted()
    }
}
