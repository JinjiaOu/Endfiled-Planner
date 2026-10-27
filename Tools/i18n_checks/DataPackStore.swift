import Foundation
// Test adapter: production catalogs and algorithms are compiled unchanged.
enum DataPackStore {
    static let root = URL(fileURLWithPath: CommandLine.arguments[1])
    static func decode<T: Decodable>(_ type: T.Type, resource name: String, withExtension ext: String = "json") -> T? {
        guard let data = try? Data(contentsOf: root.appendingPathComponent("\(name).\(ext)")) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
