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
    static var isEnglish: Bool { Locale.preferredLanguages.first?.hasPrefix("en") == true }

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
