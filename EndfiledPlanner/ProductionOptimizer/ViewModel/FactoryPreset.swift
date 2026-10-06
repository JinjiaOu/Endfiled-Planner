//
//  FactoryPreset.swift
//  EndfiledPlanner
//
//  Created by Jinjia Ou on 9/20/26.
//

import Foundation

/// 内置预设产线：存档格式的 JSON（Tools/gen_presets.py 生成并校验过摆放、连线和满载），
/// 加载时整体替换当前布局（不自动保存）
enum FactoryPreset: String, CaseIterable, Identifiable {
    case valley4Battery = "preset_valley4_battery"
    case wulingEquipment = "preset_wuling_equip"

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .valley4Battery:  return "预设：高容谷地电池（四号谷地）"
        case .wulingEquipment: return "预设：灼铜装备原件（武陵）"
        }
    }

    var summary: String {
        switch self {
        case .valley4Battery:
            return "从仓库取源矿、蓝铁矿、砂叶，满载产出高容谷地电池 6 个/分钟。将切换到四号谷地并替换当前布局（不会自动保存）。"
        case .wulingEquipment:
            return "从仓库取赤铜矿、稳定碳块，满载产出灼铜装备原件 6 个/分钟。将切换到武陵并替换当前布局（不会自动保存）。"
        }
    }

    func load() -> FactoryLayout? {
        guard let url = Bundle.main.url(forResource: rawValue, withExtension: "json") else {
            print("未找到预设 \(rawValue).json")
            return nil
        }
        do {
            return try JSONDecoder().decode(FactoryLayout.self, from: Data(contentsOf: url))
        } catch {
            print("预设 \(rawValue) 解析失败:", error)
            return nil
        }
    }
}

extension FactoryViewModel {
    func loadPreset(_ preset: FactoryPreset) {
        guard var loaded = preset.load() else { return }
        FactoryGridModel.ensureProtocolCore(in: &loaded)
        layout = loaded
        editMode = .select
        selectedBuildingID = nil
        beltStart = nil
        beltPreviewSegments = []
        clearSelection()
        refreshStats()
    }
}
