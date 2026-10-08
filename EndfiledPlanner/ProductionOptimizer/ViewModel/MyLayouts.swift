//
//  MyLayouts.swift
//  EndfiledPlanner
//

import Foundation
import Combine

// MARK: - 我的布局（M4 第 2 步）
// 框选的一组建筑 + 跟着它们走的线存成一份"布局"，以后可以整组放到别处（第 3 步）。
// 坐标都换成相对布局左上角；建筑带着全部设置（朝向、配方、反应池多选、取货材料、准入口限速/过滤、
// 输出口分配、协议核心出货口、开关状态）。缩略图不存图片，列表里按数据现画

struct SavedLayout: Identifiable, Codable {
    let id: UUID
    var name: String
    let createdAt: Date
    /// 从哪张地图存的
    let mapType: MapType
    /// 建筑，origin 是相对布局左上角的坐标
    let buildings: [PlacedBuilding]
    /// 线，格子坐标同样是相对的
    let belts: [Belt]
    /// 外框大小（格），缩略图和以后放置预览用
    let width: Int
    let height: Int

    var buildingCount: Int { buildings.count }
}

/// 存在 App 自己的文件夹里（Application Support/my_layouts.json），先只存本机
final class MyLayoutStore: ObservableObject {
    @Published private(set) var layouts: [SavedLayout] = []

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("my_layouts.json")
    }()

    init() {
        load()
    }

    func add(_ layout: SavedLayout) {
        layouts.insert(layout, at: 0)
        persist()
    }

    func rename(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let idx = layouts.firstIndex(where: { $0.id == id }) else { return }
        layouts[idx].name = trimmed
        persist()
    }

    func delete(_ id: UUID) {
        layouts.removeAll { $0.id == id }
        persist()
    }

    /// 默认名字："我的布局 3"这种，跳过已经用掉的编号
    func suggestedName() -> String {
        var n = layouts.count + 1
        let names = Set(layouts.map(\.name))
        while names.contains("我的布局 \(n)") { n += 1 }
        return "我的布局 \(n)"
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            layouts = try JSONDecoder().decode([SavedLayout].self, from: data)
        } catch {
            print("我的布局读取失败:", error)
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(layouts)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("我的布局保存失败:", error)
        }
    }
}

extension FactoryViewModel {
    /// 把当前框选的建筑、跟着它们走的线（见 beltsMovingWithGroup）和选中的线存成一份布局；没选建筑返回 nil。
    /// 选中的线哪怕一头接在组外建筑上（比如从协议核心拉出来的线，核心不会被选进组里）也存，
    /// 放出来时那头空着，放到对应位置就能接上
    func makeSavedLayout(name: String) -> SavedLayout? {
        let buildings = groupBuildings
        guard !buildings.isEmpty else { return nil }
        let movingIDs = beltsMovingWithGroup().union(groupBeltSelection)
        let belts = layout.beltNetwork.belts.filter { movingIDs.contains($0.id) }

        var cells: [GridPoint] = []
        for placed in buildings {
            guard let def = BuildingDefinition.find(placed.definitionID) else { continue }
            cells += placed.occupiedCells(definition: def)
        }
        cells += belts.flatMap { $0.segments.map(\.cell) }
        let minCol = cells.map(\.col).min() ?? 0, maxCol = cells.map(\.col).max() ?? 0
        let minRow = cells.map(\.row).min() ?? 0, maxRow = cells.map(\.row).max() ?? 0
        let shift = GridPoint(col: -minCol, row: -minRow)

        let relBuildings = buildings.map { placed -> PlacedBuilding in
            var copy = placed
            copy.origin = placed.origin + shift
            return copy
        }
        let relBelts = belts.map { belt -> Belt in
            var copy = belt
            for i in copy.segments.indices { copy.segments[i].cell = copy.segments[i].cell + shift }
            return copy
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return SavedLayout(id: UUID(), name: trimmed.isEmpty ? "未命名布局" : trimmed, createdAt: .now,
                           mapType: layout.mapType, buildings: relBuildings, belts: relBelts,
                           width: maxCol - minCol + 1, height: maxRow - minRow + 1)
    }
}
