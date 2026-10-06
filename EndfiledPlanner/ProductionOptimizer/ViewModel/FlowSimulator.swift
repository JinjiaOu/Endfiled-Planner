//
//  FlowSimulator.swift
//  EndfiledPlanner
//
//  Created by Jinjia Ou on 9/20/26.
//

import Foundation

/// 顺着传送带/管道网络算"理论稳定吞吐量"：
/// 每台生产设备有一个节流系数 t（0~1），从 t=1 开始反复迭代——
/// 前向传播算出各口到货量（受带速/管速、分流均分、汇流上限、准入口限速约束），
/// 终点消耗方给出"到货里实际被吃掉的比例"，再沿网络反推回上游设备的出货通畅度，
/// 用 t = min(原料满足度, t × 出货通畅度) 更新，直到数字不再变化（有最大迭代次数兜底）。
/// 只算理论稳态：不管仓库存量/原料耗尽/启动时的死锁。
enum FlowSimulator {

    // MARK: - 常量（单位：个/秒）
    static let beltCapacity = 0.5
    /// 管道上限：表里 msPerRound=500,volume=1 推算是 2/s，用户 2026-10-02 确认就是 2/s
    static let pipeCapacity = 2.0
    /// 转化机/气体散布机的激活消耗：最低 6/min，低于就整台停机
    static let activatorNeed = 0.1
    /// 废水处理机自身的消耗上限（msPerRound 2000）
    static let cleanerRate = 0.5
    /// 气体散布机的影响范围（向外扩几格）
    static let vaporizerRange = 5
    static let maxIterations = 400
    static let epsilon = 1e-7

    static let cleanerAccepted: Set<String> = ["污水", "壤晶废液", "惰性壤晶废液"]
    /// 散布机吃的气体 → 产生的环境
    static let vaporizerGases: [String: String] = ["惰气": "稳定", "水蒸气": "潮湿", "酸气": "酸性", "息壤气": "息壤"]
    /// 转化机激活口要求的物品
    static let transmuterActivators: [String: String] = ["transmuter_1": "液化息壤", "transmuter_2": "息壤气"]

    // MARK: - 反应池 / 扩容反应池：多配方自我供给的净流量计算
    // 同时生效的几条配方，同一物品的产出和消耗互相抵消（净零就是纯内部循环，不占对外的口），
    // 剩下的净缺口/净盈余才是真正要接传送带/管道的外部原料/产物
    struct NetItem {
        let name: String
        let net: Double   // 正 = 净产出，负 = 净消耗，0 = 纯内部循环
        let isSolid: Bool
    }

    static func computeNetFlows(_ recipes: [Recipe]) -> [NetItem] {
        var net: [String: Double] = [:]
        for recipe in recipes {
            let seconds = Double(max(recipe.time, 1))
            for input in recipe.inputs { net[input.name, default: 0] -= Double(input.count) / seconds }
            for output in recipe.outputs { net[output.name, default: 0] += Double(output.count) / seconds }
        }
        return net.map { NetItem(name: $0.key, net: $0.value, isSolid: ItemCatalog.isSolid($0.key)) }
    }

    struct SelfSupplyAnalysis {
        let netItems: [NetItem]
        /// 总共涉及的物品种类（含净零的纯内部循环），要跟 multiRecipeItemCapacity 比
        var totalDistinctItems: Int { netItems.count }
        var externalInputs: [NetItem] { netItems.filter { $0.net < -1e-9 } }
        var externalOutputs: [NetItem] { netItems.filter { $0.net > 1e-9 } }
        var externalLiquidOutputs: [NetItem] { externalOutputs.filter { !$0.isSolid } }
        var externalSolidOutputs: [NetItem] { externalOutputs.filter { $0.isSolid } }
        var exceedsCapacity = false
        var exceedsOutputCap = false
    }

    static func analyzeSelfSupply(recipes: [Recipe], capacity: Int?) -> SelfSupplyAnalysis {
        let netItems = computeNetFlows(recipes)
        var analysis = SelfSupplyAnalysis(netItems: netItems)
        if let capacity { analysis.exceedsCapacity = analysis.totalDistinctItems > capacity }
        analysis.exceedsOutputCap =
            analysis.externalLiquidOutputs.count > BuildingDefinition.multiRecipeMaxExternalLiquidOutputs ||
            analysis.externalSolidOutputs.count > BuildingDefinition.multiRecipeMaxExternalSolidOutputs
        return analysis
    }

    // MARK: - 结果
    enum MachineStatus {
        case running, starved, blocked, inactive, noRecipe

        var label: String {
            switch self {
            case .running:  return "生产中"
            case .starved:  return "原料不足"
            case .blocked:  return "阻塞"
            case .inactive: return "未激活"
            case .noRecipe: return "未设置"
            }
        }
    }

    struct MachineState: Identifiable {
        let id: UUID
        let name: String
        let status: MachineStatus
        let throttle: Double
        let detail: String?
        /// 实际产出（个/秒）
        let outputs: [String: Double]
        /// 实际消耗（个/秒），含激活口/散布机吃掉的气体或液体
        let inputs: [String: Double]
        /// 各原料的到货量 / 满载需求（个/秒），详情面板用
        var arrivals: [String: Double] = [:]
        var needs: [String: Double] = [:]
        /// 激活口（转化机）或进气口（气体散布机）要的物品和实际到货量（个/秒）
        var activatorItem: String? = nil
        var activatorArrival: Double = 0
        /// 仓库取货口不算产线
        let isWarehouseOutlet: Bool
    }

    struct SinkState: Identifiable {
        let id: UUID
        let name: String
        /// 实际消耗（个/秒）
        let consumed: [String: Double]
    }

    /// 一条传送带/管道的流量
    struct BeltFlow {
        /// 实际流量（个/秒），按物品
        let flow: [String: Double]
        /// 上限（个/秒）
        let capacity: Double
        /// 上游想塞进来的量超过上限（被限流）
        let isOverCapacity: Bool
        let fromName: String
        /// nil = 线尾没接到任何入口，货送不出去
        let toName: String?

        var total: Double { flow.values.reduce(0, +) }
    }

    /// 热能池：按实际到货的燃料算发电量
    struct GeneratorState: Identifiable {
        let id: UUID
        let name: String
        /// 正在烧的燃料（有多种到货时烧发电最高的那种），nil = 没有燃料
        let fuel: String?
        /// 实际发电（MW）：燃料发电量 × 到货满足度
        let power: Double
        /// 燃料到货满足度 0~1
        let fuelRatio: Double
    }

    struct Result {
        var machines: [MachineState] = []
        var sinks: [SinkState] = []
        var generators: [GeneratorState] = []
        /// 需要供电但不在任何供电桩范围内的建筑
        var unpoweredIDs: Set<UUID> = []
        /// 每条传送带/管道的实际流量（只有线头接在某个出口上的线才有）
        var beltFlows: [UUID: BeltFlow] = [:]
        var converged = true
        var iterations = 0

        func machineState(for id: UUID) -> MachineState? {
            machines.first { $0.id == id }
        }
    }

    static func simulate(layout: FactoryLayout, recipesFor: (BuildingDefinition) -> [Recipe]) -> Result {
        Engine(layout: layout, recipesFor: recipesFor).run()
    }
}

// MARK: - 内部结构

private enum NodeKind {
    case machine, unloader, loader, cleaner
    case splitter, converger, bridge, conditioner
    case vaporizer, generator, ignored

    var isRouter: Bool {
        self == .splitter || self == .converger || self == .bridge || self == .conditioner
    }
}

private struct PortInfo {
    let port: BuildingPort
    let cell: GridPoint
    let facing: BuildingRotation
    var linkIndex: Int? = nil

    var external: GridPoint {
        GridPoint(col: cell.col + facing.outputOffset.col, row: cell.row + facing.outputOffset.row)
    }
    var isInput: Bool { port.ioDirection == .input }
    var isOutput: Bool { port.ioDirection == .output }
}

private struct Bounds {
    let minCol: Int, maxCol: Int, minRow: Int, maxRow: Int

    func overlaps(_ other: Bounds, expandedBy e: Int) -> Bool {
        other.maxCol >= minCol - e && other.minCol <= maxCol + e &&
        other.maxRow >= minRow - e && other.minRow <= maxRow + e
    }
}

private final class Node {
    let placed: PlacedBuilding
    let def: BuildingDefinition
    let kind: NodeKind
    var ports: [PortInfo]
    let bounds: Bounds

    var recipe: Recipe? = nil
    var hasRecipeConfigured = false
    var ingredients: [(name: String, rate: Double)] = []
    var products: [(name: String, rate: Double)] = []
    var requiredEnv: String? = nil
    var activatorPort: Int? = nil
    var activatorItem: String? = nil
    var conditionerLimit = Double.infinity

    var throttle = 1.0
    var tIn = 1.0
    var rMin = 1.0
    var limitingItem: String? = nil
    var gateNote: String? = nil
    var conditionerScale = 1.0
    var activeEnv: String? = nil
    var consumed: [String: Double] = [:]
    /// 需要供电但不在供电桩范围内：不运行
    var unpowered = false
    var generated = 0.0
    var generatorFuel: String? = nil
    var fuelRatio = 0.0
    var lastArrivals: [String: Double] = [:]
    var lastActivatorArrival: [String: Double] = [:]

    init(placed: PlacedBuilding, def: BuildingDefinition, kind: NodeKind, ports: [PortInfo]) {
        self.placed = placed
        self.def = def
        self.kind = kind
        self.ports = ports
        let cells = placed.occupiedCells(definition: def)
        bounds = Bounds(minCol: cells.map { $0.col }.min() ?? 0, maxCol: cells.map { $0.col }.max() ?? 0,
                        minRow: cells.map { $0.row }.min() ?? 0, maxRow: cells.map { $0.row }.max() ?? 0)
    }
}

private final class Link {
    let kind: PortKind
    let capacity: Double
    var fromNode = -1
    var toNode = -1          // -1 = 末端没接到任何口，流量过不去
    /// 由哪条传送带/管道形成的连接；建筑口直接贴口的连接没有
    var beltID: UUID? = nil
    var offer: [String: Double] = [:]
    var flow: [String: Double] = [:]
    var capScale = 1.0
    /// 到货里最终被消耗掉的比例（按物品）
    var passFlow: [String: Double] = [:]

    init(kind: PortKind) {
        self.kind = kind
        capacity = kind == .item ? FlowSimulator.beltCapacity : FlowSimulator.pipeCapacity
    }

    func passOffer(_ item: String) -> Double {
        capScale * (passFlow[item] ?? 0)
    }
}

// MARK: - 引擎

private final class Engine {
    var nodes: [Node] = []
    var links: [Link] = []
    var producers: [Int] = []
    var routerOrder: [Int] = []
    var vaporizers: [Int] = []
    var terminals: [Int] = []
    var iterations = 0

    init(layout: FactoryLayout, recipesFor: (BuildingDefinition) -> [Recipe]) {
        buildNodes(layout: layout, recipesFor: recipesFor)
        markPowerCoverage()
        buildLinks(layout: layout)
        classifyNodes()
    }

    // MARK: 建图

    private func nodeKind(for def: BuildingDefinition) -> NodeKind {
        switch def.id {
        case BuildingDefinition.warehouseOutletID: return .unloader
        case BuildingDefinition.warehouseInletID:  return .loader
        case "liquid_cleaner_1":                   return .cleaner
        case "log_splitter", "log_pipe_splitter":  return .splitter
        case "log_converger", "log_pipe_converger": return .converger
        case "log_connector", "log_pipe_connector": return .bridge
        case "log_conditioner", "log_pipe_conditioner": return .conditioner
        case "vaporizer_1":                        return .vaporizer
        case "power_station_1":                    return .generator
        default:
            switch def.category {
            case .production, .synthesis, .extraction: return .machine
            default: return .ignored
            }
        }
    }

    private func buildNodes(layout: FactoryLayout, recipesFor: (BuildingDefinition) -> [Recipe]) {
        for placed in layout.buildings where placed.isActive {
            guard let def = BuildingDefinition.find(placed.definitionID) else { continue }
            let ports = def.ports.map { port -> PortInfo in
                let resolved = port.resolvedPosition(placed: placed, definition: def)
                return PortInfo(port: port, cell: resolved.cell, facing: resolved.facing)
            }
            let node = Node(placed: placed, def: def, kind: nodeKind(for: def), ports: ports)
            configure(node, recipesFor: recipesFor)
            nodes.append(node)
        }
    }

    private func configure(_ node: Node, recipesFor: (BuildingDefinition) -> [Recipe]) {
        switch node.kind {
        case .machine:
            let recipes = recipesFor(node.def)
            if node.def.isMultiRecipeMachine {
                let selected = recipes.filter { node.placed.selectedRecipeIDs.contains($0.id) }
                if !selected.isEmpty {
                    node.hasRecipeConfigured = true
                    let net = FlowSimulator.computeNetFlows(selected)
                    node.ingredients = net.filter { $0.net < -1e-9 }.map { ($0.name, -$0.net) }
                    node.products = net.filter { $0.net > 1e-9 }.map { ($0.name, $0.net) }
                }
            } else if let recipeID = node.placed.selectedRecipeID,
                      let recipe = recipes.first(where: { $0.id == recipeID }) {
                let seconds = Double(max(recipe.time, 1))
                node.recipe = recipe
                node.hasRecipeConfigured = true
                node.ingredients = recipe.inputs.map { ($0.name, Double($0.count) / seconds) }
                node.products = recipe.outputs.map { ($0.name, Double($0.count) / seconds) }
                node.requiredEnv = recipe.requiredEnv
            }
            if let item = FlowSimulator.transmuterActivators[node.def.id] {
                node.activatorItem = item
                node.activatorPort = node.ports.firstIndex {
                    $0.isInput && $0.port.kind == .pipe && $0.port.edge == .down
                }
            }
        case .vaporizer:
            node.activatorPort = node.ports.firstIndex { $0.isInput && $0.port.kind == .pipe }
        case .unloader:
            if let materialID = node.placed.outletMaterialID, let material = ItemCatalog.name(for: materialID) {
                node.products = [(material, FlowSimulator.beltCapacity)]
            }
        case .conditioner:
            let cap = node.def.id == "log_pipe_conditioner" ? FlowSimulator.pipeCapacity : FlowSimulator.beltCapacity
            if let perMin = node.placed.flowLimitPerMin {
                node.conditionerLimit = min(cap, max(perMin, 0) / 60)
            } else {
                node.conditionerLimit = cap
            }
        default:
            break
        }
    }

    /// 供电：所有供电桩视为同一张电网，建筑本体只要跟任一供电桩的范围（本体向四周扩 powerRange 格）有重叠就算通电。
    /// 协议核心和热能池只发电，自己不带供电范围
    private func markPowerCoverage() {
        let diffusers = nodes.compactMap { node in node.def.powerRange.map { (node.bounds, $0) } }
        for node in nodes where node.def.needsPower {
            node.unpowered = !diffusers.contains { bounds, range in bounds.overlaps(node.bounds, expandedBy: range) }
        }
    }

    private func portKey(_ cell: GridPoint, _ kind: PortKind) -> String {
        "\(cell.col),\(cell.row),\(kind.rawValue)"
    }

    private func buildLinks(layout: FactoryLayout) {
        var outputByExternal: [String: (node: Int, port: Int)] = [:]
        var inputByExternal: [String: (node: Int, port: Int)] = [:]
        var inputByCell: [String: (node: Int, port: Int)] = [:]
        for (ni, node) in nodes.enumerated() {
            for (pi, p) in node.ports.enumerated() {
                let key = portKey(p.external, p.port.kind)
                if p.isOutput {
                    if outputByExternal[key] == nil { outputByExternal[key] = (ni, pi) }
                } else {
                    if inputByExternal[key] == nil { inputByExternal[key] = (ni, pi) }
                    let cellKey = portKey(p.cell, p.port.kind)
                    if inputByCell[cellKey] == nil { inputByCell[cellKey] = (ni, pi) }
                }
            }
        }

        func connect(kind: PortKind, from: (node: Int, port: Int), to: (node: Int, port: Int)?, beltID: UUID? = nil) {
            let link = Link(kind: kind)
            link.beltID = beltID
            let index = links.count
            link.fromNode = from.node
            nodes[from.node].ports[from.port].linkIndex = index
            if let to, nodes[to.node].ports[to.port].linkIndex == nil {
                link.toNode = to.node
                nodes[to.node].ports[to.port].linkIndex = index
            }
            links.append(link)
        }

        // 传送带/管道：头对着输出口外面那一格，尾对着输入口外面那一格
        for belt in layout.beltNetwork.belts {
            guard let head = belt.headCell, let tail = belt.tailCell else { continue }
            let kind: PortKind = belt.lineType == .belt ? .item : .pipe
            guard let from = outputByExternal[portKey(head, kind)],
                  nodes[from.node].ports[from.port].linkIndex == nil
            else { continue }
            connect(kind: kind, from: from, to: inputByExternal[portKey(tail, kind)], beltID: belt.id)
        }

        // 建筑口直接贴口（中间没有线）：输出口外面那格正好是对方输入口所在格，对方输入口外面那格也正好是我的口
        for ni in nodes.indices {
            for pi in nodes[ni].ports.indices {
                let p = nodes[ni].ports[pi]
                guard p.isOutput, p.linkIndex == nil,
                      let target = inputByCell[portKey(p.external, p.port.kind)],
                      target.node != ni,
                      nodes[target.node].ports[target.port].linkIndex == nil,
                      nodes[target.node].ports[target.port].external == p.cell
                else { continue }
                connect(kind: p.port.kind, from: (ni, pi), to: target)
            }
        }
    }

    private func classifyNodes() {
        for (i, node) in nodes.enumerated() {
            switch node.kind {
            case .machine:
                producers.append(i); terminals.append(i)
            case .unloader:
                producers.append(i)
            case .vaporizer:
                vaporizers.append(i)
            case .loader, .cleaner, .generator, .ignored:
                terminals.append(i)
            default:
                break
            }
        }

        // 分流/汇流/桥/准入口之间的拓扑序（有环时剩下的按原顺序追加，靠迭代逼近）
        let routers = nodes.indices.filter { nodes[$0].kind.isRouter }
        var indegree: [Int: Int] = [:]
        for r in routers { indegree[r] = 0 }
        for link in links where link.fromNode >= 0 && link.toNode >= 0 {
            if nodes[link.fromNode].kind.isRouter && nodes[link.toNode].kind.isRouter {
                indegree[link.toNode, default: 0] += 1
            }
        }
        var queue = routers.filter { indegree[$0] == 0 }
        var visited = Set<Int>()
        while !queue.isEmpty {
            let r = queue.removeFirst()
            guard visited.insert(r).inserted else { continue }
            routerOrder.append(r)
            for pi in nodes[r].ports.indices {
                guard let li = nodes[r].ports[pi].linkIndex, links[li].fromNode == r, links[li].toNode >= 0,
                      nodes[links[li].toNode].kind.isRouter
                else { continue }
                let next = links[li].toNode
                indegree[next, default: 0] -= 1
                if indegree[next] == 0 { queue.append(next) }
            }
        }
        for r in routers where !visited.contains(r) { routerOrder.append(r) }
    }

    // MARK: 工具

    private func portKind(for item: String) -> PortKind {
        ItemCatalog.isSolid(item) ? .item : .pipe
    }

    private func inputLinks(_ node: Node) -> [Int] {
        node.ports.compactMap { $0.isInput ? $0.linkIndex : nil }
    }

    private func outputLinks(_ node: Node) -> [Int] {
        node.ports.compactMap { $0.isOutput ? $0.linkIndex : nil }
    }

    /// 一般机器不用管走哪个口，所有同类型输出口平均分；反应池/扩容反应池净产出可能不止一种，
    /// 同类型口有几个净产物时必须按用户手动指定的 outputPortAssignments 走各自的口，
    /// 不然会把两种液体都各分一半糊到两个管道口上，接错下游
    private func outputLinks(_ node: Node, for item: String) -> [Int] {
        let kind = portKind(for: item)
        let allOfKind = node.ports.enumerated().filter { $0.element.isOutput && $0.element.port.kind == kind }
        let assignments = node.placed.outputPortAssignments
        if !assignments.isEmpty {
            let assignedToThis = allOfKind.filter { assignments[$0.offset] == item }
            if !assignedToThis.isEmpty { return assignedToThis.compactMap { $0.element.linkIndex } }
            // 没给这个物品单独指定口：退回到"没被指定给别的物品"的口，避免抢别人已经分配好的口
            let unassigned = allOfKind.filter { assignments[$0.offset] == nil }
            if !unassigned.isEmpty { return unassigned.compactMap { $0.element.linkIndex } }
        }
        return allOfKind.compactMap { $0.element.linkIndex }
    }

    private func finalize(_ li: Int) {
        let link = links[li]
        let total = link.offer.values.reduce(0, +)
        link.capScale = total > link.capacity ? link.capacity / total : 1
        link.flow = link.offer.mapValues { $0 * link.capScale }
    }

    // MARK: 一轮迭代

    private func step() -> Double {
        for link in links {
            link.offer = [:]; link.flow = [:]; link.capScale = 1; link.passFlow = [:]
        }
        for node in nodes { node.consumed = [:]; node.gateNote = nil }

        for i in producers { push(nodes[i]) }
        for i in routerOrder { forward(nodes[i]) }
        for li in links.indices { finalize(li) }
        for i in vaporizers { evaluateVaporizer(nodes[i]) }
        for i in terminals { evaluateTerminal(nodes[i]) }
        for i in routerOrder.reversed() { backward(nodes[i]) }

        var maxDelta = 0.0
        for i in producers {
            let node = nodes[i]
            var r = 1.0
            for product in node.products where product.rate > 0 {
                let outs = outputLinks(node, for: product.name)
                let rx = outs.isEmpty ? 0 : outs.map { links[$0].passOffer(product.name) }.reduce(0, +) / Double(outs.count)
                r = min(r, rx)
            }
            node.rMin = r
            let newThrottle = max(0, min(node.throttle, node.tIn, node.throttle * r))
            maxDelta = max(maxDelta, abs(newThrottle - node.throttle))
            node.throttle = newThrottle
        }
        return maxDelta
    }

    private func push(_ node: Node) {
        for product in node.products {
            let outs = outputLinks(node, for: product.name)
            guard !outs.isEmpty else { continue }
            let amount = product.rate * node.throttle / Double(outs.count)
            for li in outs { links[li].offer[product.name, default: 0] += amount }
        }
        for li in outputLinks(node) { finalize(li) }
    }

    private func forward(_ node: Node) {
        let ins = inputLinks(node)
        let outs = outputLinks(node)
        switch node.kind {
        case .splitter:
            guard let inL = ins.first, !outs.isEmpty else { return }
            finalize(inL)
            for (item, value) in links[inL].flow {
                for o in outs { links[o].offer[item, default: 0] += value / Double(outs.count) }
            }
        case .converger:
            guard let outL = outs.first else { return }
            for inL in ins {
                finalize(inL)
                for (item, value) in links[inL].flow { links[outL].offer[item, default: 0] += value }
            }
        case .bridge:
            for p in node.ports where p.isInput {
                guard let inL = p.linkIndex,
                      let outL = node.ports.first(where: { $0.isOutput && $0.facing == p.facing.opposite })?.linkIndex
                else { continue }
                finalize(inL)
                for (item, value) in links[inL].flow { links[outL].offer[item, default: 0] += value }
            }
        case .conditioner:
            guard let inL = ins.first, let outL = outs.first else { return }
            finalize(inL)
            let total = links[inL].flow.values.reduce(0, +)
            let scale = total > node.conditionerLimit ? node.conditionerLimit / total : 1
            node.conditionerScale = scale
            for (item, value) in links[inL].flow { links[outL].offer[item, default: 0] += value * scale }
        default:
            break
        }
        for o in outs { finalize(o) }
    }

    private func backward(_ node: Node) {
        let ins = inputLinks(node)
        let outs = outputLinks(node)
        switch node.kind {
        case .splitter:
            guard let inL = ins.first, !outs.isEmpty else { return }
            for item in links[inL].flow.keys {
                links[inL].passFlow[item] = outs.map { links[$0].passOffer(item) }.reduce(0, +) / Double(outs.count)
            }
        case .converger:
            guard let outL = outs.first else { return }
            for inL in ins {
                for item in links[inL].flow.keys { links[inL].passFlow[item] = links[outL].passOffer(item) }
            }
        case .bridge:
            for p in node.ports where p.isInput {
                guard let inL = p.linkIndex,
                      let outL = node.ports.first(where: { $0.isOutput && $0.facing == p.facing.opposite })?.linkIndex
                else { continue }
                for item in links[inL].flow.keys { links[inL].passFlow[item] = links[outL].passOffer(item) }
            }
        case .conditioner:
            guard let inL = ins.first, let outL = outs.first else { return }
            for item in links[inL].flow.keys {
                links[inL].passFlow[item] = node.conditionerScale * links[outL].passOffer(item)
            }
        default:
            break
        }
    }

    // MARK: 终点

    private func evaluateVaporizer(_ node: Node) {
        node.activeEnv = nil
        guard let pi = node.activatorPort, let li = node.ports[pi].linkIndex else { return }
        let flow = links[li].flow
        node.lastActivatorArrival = flow
        var best: (gas: String, rate: Double)? = nil
        for (gas, _) in FlowSimulator.vaporizerGases {
            let rate = flow[gas] ?? 0
            if rate >= FlowSimulator.activatorNeed - 1e-9, rate > (best?.rate ?? 0) { best = (gas, rate) }
        }
        if let best {
            node.activeEnv = FlowSimulator.vaporizerGases[best.gas]
            links[li].passFlow[best.gas] = min(1, FlowSimulator.activatorNeed / best.rate)
        } else {
            node.gateNote = "气体不足（需要 ≥6/min）"
        }
    }

    private func envSatisfied(for node: Node, env: String) -> Bool {
        vaporizers.contains { vi in
            nodes[vi].activeEnv == env && nodes[vi].bounds.overlaps(node.bounds, expandedBy: FlowSimulator.vaporizerRange)
        }
    }

    private func evaluateTerminal(_ node: Node) {
        switch node.kind {
        case .machine:  evaluateMachine(node)
        case .loader:
            for li in inputLinks(node) {
                for (item, value) in links[li].flow {
                    links[li].passFlow[item] = 1
                    node.consumed[item, default: 0] += value
                }
            }
        case .generator:
            evaluateGenerator(node)
        case .cleaner:
            guard !node.unpowered else { break }   // 没通电什么都不收，上游被堵住
            for li in inputLinks(node) {
                let accepted = links[li].flow.filter { FlowSimulator.cleanerAccepted.contains($0.key) }.values.reduce(0, +)
                let fraction = accepted > 0 ? min(1, FlowSimulator.cleanerRate / accepted) : 1
                for (item, value) in links[li].flow where FlowSimulator.cleanerAccepted.contains(item) {
                    links[li].passFlow[item] = fraction
                    node.consumed[item, default: 0] += value * fraction
                }
            }
        default:
            break   // 没配置好的建筑什么都不收，passFlow 保持 0，上游会被堵住
        }
    }

    private func evaluateMachine(_ node: Node) {
        var arrivals: [String: Double] = [:]
        var activatorArrival: [String: Double] = [:]
        for (pi, p) in node.ports.enumerated() where p.isInput {
            guard let li = p.linkIndex else { continue }
            if pi == node.activatorPort {
                for (item, value) in links[li].flow { activatorArrival[item, default: 0] += value }
            } else {
                for (item, value) in links[li].flow { arrivals[item, default: 0] += value }
            }
        }

        node.lastArrivals = arrivals
        node.lastActivatorArrival = activatorArrival
        var t = 1.0
        node.limitingItem = nil
        if !node.hasRecipeConfigured { t = 0 }
        for ingredient in node.ingredients where ingredient.rate > 0 {
            let ratio = (arrivals[ingredient.name] ?? 0) / ingredient.rate
            if ratio < t { t = ratio; node.limitingItem = ingredient.name }
        }
        if let env = node.requiredEnv, !envSatisfied(for: node, env: env) {
            t = 0
            node.gateNote = "需要\(env)环境（附近 \(FlowSimulator.vaporizerRange) 格内要有气体散布机供气）"
        }
        if node.unpowered {
            t = 0
            node.gateNote = "未通电（不在供电桩范围内）"
        }
        var activatorOK = true
        if let item = node.activatorItem {
            let rate = activatorArrival[item] ?? 0
            activatorOK = node.activatorPort != nil && rate >= FlowSimulator.activatorNeed - 1e-9
            if !activatorOK {
                t = 0
                node.gateNote = "\(item)注入不足（需要 ≥6/min）"
            }
            if let pi = node.activatorPort, let li = node.ports[pi].linkIndex, activatorOK {
                links[li].passFlow[item] = min(1, FlowSimulator.activatorNeed / rate)
            }
        }
        node.tIn = max(0, min(1, t))

        let needByItem = Dictionary(node.ingredients.map { ($0.name, $0.rate) }, uniquingKeysWith: +)
        for (pi, p) in node.ports.enumerated() where p.isInput && pi != node.activatorPort {
            guard let li = p.linkIndex else { continue }
            for item in links[li].flow.keys {
                let arrived = arrivals[item] ?? 0
                if let need = needByItem[item], arrived > 0 {
                    links[li].passFlow[item] = min(1, node.tIn * need / arrived)
                } else {
                    links[li].passFlow[item] = 0
                }
            }
        }
    }

    /// 热能池同一时间只烧一种燃料：到货里挑发电量最高的那种，按"到货 / 满烧需要量"折算发电；其它燃料堵住不收
    private func evaluateGenerator(_ node: Node) {
        var arrivals: [String: Double] = [:]
        for li in inputLinks(node) {
            for (item, value) in links[li].flow { arrivals[item, default: 0] += value }
        }
        let best = arrivals.compactMap { item, rate -> (FuelInfo, Double)? in
            guard rate > 1e-9, let fuel = FuelCatalog.byName[item] else { return nil }
            return (fuel, rate)
        }.max { $0.0.powerProvide < $1.0.powerProvide }
        node.generatorFuel = best?.0.name
        node.fuelRatio = 0
        node.generated = 0
        if let best {
            let need = 1 / best.0.secondsPerItem
            node.fuelRatio = min(1, best.1 / need)
            node.generated = best.0.powerProvide * node.fuelRatio
            node.consumed[best.0.name] = min(best.1, need)
        }
        for li in inputLinks(node) {
            for item in links[li].flow.keys {
                if let best, item == best.0.name {
                    links[li].passFlow[item] = min(1, (1 / best.0.secondsPerItem) / best.1)
                } else {
                    links[li].passFlow[item] = 0
                }
            }
        }
    }

    // MARK: 运行与结果

    func run() -> FlowSimulator.Result {
        var converged = false
        for it in 0..<FlowSimulator.maxIterations {
            iterations = it + 1
            if step() < FlowSimulator.epsilon { converged = true; break }
        }
        var result = makeResult()
        result.converged = converged
        result.iterations = iterations
        return result
    }

    private func makeResult() -> FlowSimulator.Result {
        var result = FlowSimulator.Result()
        result.unpoweredIDs = Set(nodes.filter { $0.unpowered }.map { $0.placed.id })
        for link in links {
            guard let id = link.beltID else { continue }
            let offered = link.offer.values.reduce(0, +)
            result.beltFlows[id] = FlowSimulator.BeltFlow(
                flow: link.flow, capacity: link.capacity, isOverCapacity: offered > link.capacity + 1e-9,
                fromName: nodes[link.fromNode].def.name,
                toName: link.toNode >= 0 ? nodes[link.toNode].def.name : nil)
        }
        for node in nodes {
            switch node.kind {
            case .machine, .unloader:
                let isOutlet = node.kind == .unloader
                var status = FlowSimulator.MachineStatus.running
                var detail: String? = nil
                if node.kind == .unloader && node.products.isEmpty {
                    status = .noRecipe; detail = "未设置取货材料"
                } else if node.kind == .machine && !node.hasRecipeConfigured {
                    status = .noRecipe
                    detail = node.def.isMultiRecipeMachine ? "未勾选配方" : "未选择配方"
                } else if node.throttle < 0.999 {
                    if let note = node.gateNote {
                        status = .inactive; detail = note
                    } else if node.tIn < 0.999 && node.tIn <= node.throttle * node.rMin + 1e-6 {
                        status = .starved
                        detail = node.limitingItem.map { "缺少 \($0)" } ?? "原料不足"
                    } else {
                        status = .blocked; detail = "出口没接好或下游吃不下"
                    }
                }
                var outputs: [String: Double] = [:]
                for product in node.products { outputs[product.name] = product.rate * node.throttle }
                var inputs: [String: Double] = [:]
                for ingredient in node.ingredients { inputs[ingredient.name, default: 0] += ingredient.rate * node.throttle }
                if let item = node.activatorItem, node.throttle > 1e-9 {
                    inputs[item, default: 0] += FlowSimulator.activatorNeed
                }
                var state = FlowSimulator.MachineState(
                    id: node.placed.id, name: node.def.name, status: status, throttle: node.throttle,
                    detail: detail, outputs: outputs, inputs: inputs, isWarehouseOutlet: isOutlet)
                state.arrivals = node.lastArrivals
                state.needs = Dictionary(node.ingredients.map { ($0.name, $0.rate) }, uniquingKeysWith: +)
                state.activatorItem = node.activatorItem
                state.activatorArrival = node.activatorItem.map { node.lastActivatorArrival[$0] ?? 0 } ?? 0
                result.machines.append(state)
            case .vaporizer:
                let active = node.activeEnv != nil
                let gas = node.activeEnv.flatMap { env in FlowSimulator.vaporizerGases.first { $0.value == env }?.key }
                var state = FlowSimulator.MachineState(
                    id: node.placed.id, name: node.def.name, status: active ? .running : .inactive,
                    throttle: active ? 1 : 0, detail: node.activeEnv.map { "\($0)环境" } ?? node.gateNote,
                    outputs: [:], inputs: gas.map { [$0: FlowSimulator.activatorNeed] } ?? [:], isWarehouseOutlet: false)
                // 散布机进气口：报到货最多的那种气体
                if let top = node.lastActivatorArrival.max(by: { $0.value < $1.value }) {
                    state.activatorItem = top.key
                    state.activatorArrival = top.value
                }
                result.machines.append(state)
            case .loader, .cleaner:
                result.sinks.append(FlowSimulator.SinkState(id: node.placed.id, name: node.def.name, consumed: node.consumed))
            case .generator:
                result.generators.append(FlowSimulator.GeneratorState(
                    id: node.placed.id, name: node.def.name, fuel: node.generatorFuel,
                    power: node.generated, fuelRatio: node.fuelRatio))
            default:
                break
            }
        }
        return result
    }
}
