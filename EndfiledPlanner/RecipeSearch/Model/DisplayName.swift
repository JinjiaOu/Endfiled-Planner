import Foundation

/// Presentation only. Chinese names remain the keys used by recipes, simulation and saves.
enum DisplayName {
    private struct Names: Decodable {
        let items: [String: String]
        let devices: [String: String]
        let categories: [String: String]
        let modes: [String: String]
    }
    private static let names = DataPackStore.decode(Names.self, resource: "names_en")
    /// 跟界面文字用同一个判断：App 实际选中的本地化（系统按 App 支持的语言挑出来的），
    /// 不能看系统语言列表第一项——比如日语用户第二语言是英语时，界面是英文但第一项是日语
    static var isEnglish: Bool { Bundle.main.preferredLocalizations.first?.hasPrefix("en") == true }

    static func item(_ chineseName: String) -> String {
        guard isEnglish, let id = ItemCatalog.itemId(for: chineseName) else { return chineseName }
        return names?.items[id] ?? chineseName
    }
    static func device(id: String, fallback: String) -> String {
        isEnglish ? names?.devices[id] ?? fallback : fallback
    }
    private struct Devices: Decodable {
        struct Device: Decodable { let id: String; let name: String }
        let devices: [Device]
    }
    private static let deviceIDs = Dictionary(
        (DataPackStore.decode(Devices.self, resource: "devices")?.devices ?? []).map { ($0.name, $0.id) },
        uniquingKeysWith: { first, _ in first })
    static func device(_ chineseName: String) -> String {
        device(id: deviceIDs[chineseName] ?? "", fallback: chineseName)
    }
    static func category(id: String, fallback: String) -> String {
        isEnglish ? names?.categories[id] ?? fallback : fallback
    }
    static func mode(id: String, fallback: String) -> String {
        isEnglish ? names?.modes[id] ?? fallback : fallback
    }
    static func matches(_ chineseName: String, query: String) -> Bool {
        chineseName.localizedCaseInsensitiveContains(query) ||
            (ItemCatalog.itemId(for: chineseName).flatMap { names?.items[$0] }?.localizedCaseInsensitiveContains(query) ?? false)
    }
    static func hasPrefix(_ chineseName: String, query: String) -> Bool {
        chineseName.lowercased().hasPrefix(query.lowercased()) ||
            (ItemCatalog.itemId(for: chineseName).flatMap { names?.items[$0] }?.lowercased().hasPrefix(query.lowercased()) ?? false)
    }
    static func environment(_ name: String) -> String {
        guard isEnglish else { return name }
        switch name {
        case "稳定环境": return String(localized: "稳定环境")
        case "潮湿环境": return String(localized: "潮湿环境")
        case "酸性环境": return String(localized: "酸性环境")
        case "息壤环境": return String(localized: "息壤环境")
        case "稳定": return String(localized: "稳定")
        case "潮湿": return String(localized: "潮湿")
        case "酸性": return String(localized: "酸性")
        case "息壤": return String(localized: "息壤")
        default: return name
        }
    }
}

extension Recipe {
    var displayMachine: String {
        let base = machine.components(separatedBy: "（").first ?? machine
        let title = DisplayName.device(id: machineId, fallback: base)
        guard let gasEnvName else { return title }
        return DisplayName.isEnglish ? "\(title) (\(DisplayName.environment(gasEnvName)))" : machine
    }
}

extension BuildingDefinition {
    var displayName: String { DisplayName.device(id: id, fallback: name) }
}

extension BuildingMode {
    var displayName: String { DisplayName.mode(id: id, fallback: name) }
}

extension BuildingCategory {
    var displayName: String {
        let id: String
        switch self {
        case .logistics: id = "logistic"
        case .extraction: id = "source_machine"
        case .storage: id = "storage"
        case .production: id = "basic_machine"
        case .synthesis: id = "assemble_machine"
        case .power: id = "electric_machine"
        case .hub: id = "hub"
        }
        return DisplayName.category(id: id, fallback: rawValue)
    }
}

extension FlowSimulator.MachineStatus {
    /// Keep the simulator's original status text separate from the display layer.
    var displayLabel: String {
        switch self {
        case .running: return String(localized: "生产中")
        case .starved: return String(localized: "原料不足")
        case .blocked: return String(localized: "阻塞")
        case .inactive: return String(localized: "未激活")
        case .noRecipe: return String(localized: "未设置")
        }
    }
}

extension DisplayName {
    static func region(_ original: String) -> String {
        switch original {
        case "四号谷地": return String(localized: "四号谷地")
        case "武陵": return String(localized: "武陵")
        case "全部": return String(localized: "全部")
        default: return original
        }
    }

    /// Adapt the simulator's existing diagnostic messages at the presentation boundary.
    /// These messages never feed back into the simulation, dictionaries or saves.
    static func diagnostic(_ original: String) -> String {
        guard isEnglish else { return original }
        switch original {
        case "生产中": return String(localized: "生产中")
        case "原料不足": return String(localized: "原料不足")
        case "阻塞": return String(localized: "阻塞")
        case "未激活": return String(localized: "未激活")
        case "未设置": return String(localized: "未设置")
        case "气体不足（需要 ≥6/min）": return String(localized: "气体不足（需要 ≥6/min）")
        case "未通电（不在供电桩范围内）": return String(localized: "未通电（不在供电桩范围内）")
        case "未设置取货材料": return String(localized: "未设置取货材料")
        case "未勾选配方": return String(localized: "未勾选配方")
        case "未选择配方": return String(localized: "未选择配方")
        case "出口没接好或下游吃不下": return String(localized: "出口没接好或下游吃不下")
        default: break
        }
        if original.hasPrefix("缺少 ") {
            let item = item(String(original.dropFirst(3)))
            return String(localized: "缺少 \(item)")
        }
        let suffix = "注入不足（需要 ≥6/min）"
        if original.hasSuffix(suffix) {
            let item = item(String(original.dropLast(suffix.count)))
            return String(localized: "\(item)注入不足（需要 ≥6/min）")
        }
        if original.hasPrefix("需要"), let range = original.range(of: "环境（附近 ") {
            let env = environment(String(original[original.index(original.startIndex, offsetBy: 2)..<range.lowerBound]) + "环境")
            return String(localized: "需要\(env)（附近 \(FlowSimulator.vaporizerRange) 格内要有气体散布机供气）")
        }
        if original.hasPrefix("被"), let separator = original.range(of: "挡住（只放行"), original.hasSuffix("）") {
            let device = device(String(original[original.index(after: original.startIndex)..<separator.lowerBound]))
            let filter = item(String(original[separator.upperBound..<original.index(before: original.endIndex)]))
            return String(localized: "被\(device)挡住（只放行\(filter)）")
        }
        return environment(original)
    }
}
