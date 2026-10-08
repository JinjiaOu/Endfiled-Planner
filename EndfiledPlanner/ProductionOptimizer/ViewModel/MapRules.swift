//
//  MapRules.swift
//  EndfiledPlanner
//

import Foundation

/// 仓库取货口/存货口怎么接仓库
enum WarehouseLineStyle {
    /// 四号谷地：贴地图边放（只限列出的这几条边），长边整条贴死、口朝地图内部
    case perimeter(edges: Set<BuildingRotation>)
    /// 武陵：贴仓库存取线源桩或基段放；基段要连着源桩
    case busDock
}

/// 地图规则表：每张地图一条记录，跟地图有关的判断都从这里查，代码里不再到处写 `switch mapType`。
/// 以后加新地图基本只要在 `table` 里加一条（M5 的数据包也可以顺带更新这张表）
struct MapRules {
    let map: MapType
    /// 能不能用管道（画管道 + 管道分流器/汇流器/桥/准入口）；四号谷地不用水不用气，管道一起禁掉（用户 2026-10-07 定）
    let allowsPipes: Bool
    /// 仓库取线方式
    let warehouseLine: WarehouseLineStyle
    /// 这张图上不能造的建筑（别的地图专属）
    let unavailableBuildingIDs: Set<String>
    /// 这张图上不能用的配方模式（devices.json 里 modes 的 id）：机器能造，但这些模式的配方不能选
    let blockedRecipeModes: Set<String>
    /// 画布大小（格）
    let gridCols: Int
    let gridRows: Int

    /// 只能在武陵用的建筑（用户 2026-10-06 定）：用水用气的设备、暗管、储液/储气罐、拆解机、息壤供电桩、仓库存取线
    static let wulingOnlyBuildingIDs: Set<String> = [
        "pump_1", "pump_2", "gas_pump_1", "miner_4",                 // 水泵、二型耐酸水泵、气体收集泵、水驱矿机
        "mix_pool_1", "mix_pool_2",                                  // 反应池、扩容反应池
        "transmuter_1", "transmuter_2",                              // 液气转化机、固气转化机
        "liquid_purifier_1", "gas_reactor_1", "xiranite_oven_1",     // 提纯机、气体反应炉、天有洪炉
        "liquid_cleaner_1", "vaporizer_1", "dismantler_1",           // 废水处理机、气体散布机、拆解机
        "liquid_storager_1", "gas_storager_1",                       // 储液罐、储气罐
        "udpipe_loader_1", "udpipe_loader_2", "udpipe_unloader_1", "udpipe_unloader_2",  // 暗管入口/出口（含多口）
        "power_diffuser_2",                                          // 息壤供电桩
        BuildingDefinition.warehouseSourceID, BuildingDefinition.warehouseBaseSegmentID,
    ]

    /// 管道物流建筑（管道本身不是建筑，是画出来的线）
    static let pipeLogisticsIDs: Set<String> = [
        "log_pipe_splitter", "log_pipe_converger", "log_pipe_connector", "log_pipe_conditioner",
    ]

    static let table: [MapType: MapRules] = [
        .valley4: MapRules(
            map: .valley4,
            allowsPipes: false,
            warehouseLine: .perimeter(edges: [.up, .left]),
            unavailableBuildingIDs: wulingOnlyBuildingIDs,
            // 精炼炉/灌装机/塑形机/种植机两图都能放，但四号谷地只能用基础模式
            blockedRecipeModes: ["liquid", "gas", "gasliquid"],
            gridCols: 80, gridRows: 80),
        .wuling: MapRules(
            map: .wuling,
            allowsPipes: true,
            warehouseLine: .busDock,
            unavailableBuildingIDs: [],
            blockedRecipeModes: [],
            gridCols: 80, gridRows: 80),
    ]

    static func of(_ map: MapType) -> MapRules {
        table[map] ?? table[.wuling]!
    }

    func allows(_ def: BuildingDefinition) -> Bool {
        if !allowsPipes && MapRules.pipeLogisticsIDs.contains(def.id) { return false }
        return !unavailableBuildingIDs.contains(def.id)
    }

    /// 这条配方在这张图上不能用时，返回它所属的模式（给提示用）；能用返回 nil
    func blockedMode(of recipe: Recipe, on def: BuildingDefinition) -> BuildingMode? {
        guard let mode = def.mode(of: recipe), blockedRecipeModes.contains(mode.id) else { return nil }
        return mode
    }

    /// 只能在哪些地图用（给"仅武陵"这类标签用）
    static func maps(allowing def: BuildingDefinition) -> [MapType] {
        MapType.allCases.filter { of($0).allows(def) }
    }

    static func maps(allowing recipe: Recipe, on def: BuildingDefinition) -> [MapType] {
        MapType.allCases.filter { of($0).blockedMode(of: recipe, on: def) == nil }
    }
}

extension MapType {
    var rules: MapRules { MapRules.of(self) }
}
