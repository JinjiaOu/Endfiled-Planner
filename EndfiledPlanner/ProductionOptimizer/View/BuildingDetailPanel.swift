// Created by Jinjia Ou on 10/2/26.

import SwiftUI

/// 选中建筑的详情面板：iPad 放右侧浮层，iPhone 放在网格下方（不是模态弹窗，展开时网格照样能点能拖）。
/// 头部是通用信息和操作（开关/移动/旋转/收纳），下面按建筑类型显示配方、到货、激活、发电等内容
struct BuildingDetailPanel: View {
    enum Style { case side, bottom }

    @ObservedObject var vm: FactoryViewModel
    let placed: PlacedBuilding
    let def: BuildingDefinition
    let style: Style

    @State private var expanded = true
    @State private var showRecipeSheet = false
    @State private var showMaterialSheet = false
    @State private var showFilterSheet = false

    private let green = Color(red: 0.4, green: 0.8, blue: 0.2)
    private let orange = Color(red: 0.9, green: 0.5, blue: 0.2)
    private let red = Color(red: 0.9, green: 0.3, blue: 0.2)
    private let yellow = Color(red: 1.0, green: 0.8, blue: 0.0)
    private let panelBackground = Color(red: 0.10, green: 0.11, blue: 0.14)

    private var state: FlowSimulator.MachineState? {
        vm.stats.machineStates.first { $0.id == placed.id }
    }
    private var isUnpowered: Bool { vm.stats.unpoweredIDs.contains(placed.id) }
    private var isMoving: Bool { vm.movingBuildingID == placed.id }

    var body: some View {
        VStack(spacing: 0) {
            header
            if isMoving { movingBanner }
            if style == .side || expanded {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        content
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                }
                .frame(maxHeight: style == .bottom ? 300 : .infinity)
            }
        }
        .background(panelBackground)
        .overlay(Rectangle().stroke(def.category.color.opacity(0.35), lineWidth: 1))
    }

    // MARK: - 头部：名称 / 耗电 / 状态条 / 操作按钮
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ZStack {
                    Rectangle().fill(def.category.color.opacity(0.2)).frame(width: 40, height: 40)
                    Rectangle().stroke(def.category.color.opacity(0.6), lineWidth: 1.5).frame(width: 40, height: 40)
                    Image(systemName: def.category.icon).font(.system(size: 17)).foregroundColor(def.category.color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(def.name).font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                    powerLine
                }
                Spacer()
                if style == .bottom {
                    iconButton("chevron.\(expanded ? "down" : "up")", color: .white.opacity(0.6)) {
                        withAnimation(.spring(response: 0.3)) { expanded.toggle() }
                    }
                }
                iconButton("xmark", color: .white.opacity(0.6)) {
                    vm.cancelMoving()
                    vm.selectedBuildingID = nil
                }
            }
            statusBar
            HStack(spacing: 8) {
                actionButton(placed.isActive ? "关闭" : "开启", icon: "power",
                             color: placed.isActive ? green : .white.opacity(0.5)) { vm.toggleActive(placed.id) }
                actionButton(isMoving ? "取消移动" : "移动", icon: "arrow.up.and.down.and.arrow.left.and.right",
                             color: Color(red: 0.4, green: 0.7, blue: 0.9)) {
                    isMoving ? vm.cancelMoving() : vm.startMoving(placed.id)
                }
                actionButton("旋转", icon: "rotate.right", color: Color(red: 0.7, green: 0.5, blue: 0.9)) { vm.rotateSelected() }
                actionButton("收纳", icon: "tray.and.arrow.down.fill", color: red) { vm.deleteSelected() }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color(red: 0.08, green: 0.09, blue: 0.12))
    }

    @ViewBuilder
    private var powerLine: some View {
        if def.powerUsage > 0 {
            Label(String(format: "耗电功率值 %.0f MW", def.powerUsage), systemImage: "bolt.fill")
                .font(.system(size: 10, design: .monospaced)).foregroundColor(orange)
        } else if def.isProtocolCore {
            Label(String(format: "发电 %.0f MW", def.powerGenerate), systemImage: "bolt.fill")
                .font(.system(size: 10, design: .monospaced)).foregroundColor(yellow)
        } else if def.powerRange != nil || def.id == "power_station_1" {
            Label("电力设施", systemImage: "bolt.fill")
                .font(.system(size: 10, design: .monospaced)).foregroundColor(yellow)
        } else {
            Text("不耗电").font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.4))
        }
    }

    /// 状态条：关闭 / 未通电优先，其余看模拟结果的运行率
    @ViewBuilder
    private var statusBar: some View {
        let (label, ratio, color): (String, Double?, Color) = {
            if !placed.isActive { return ("已关闭", nil, .white.opacity(0.4)) }
            if isUnpowered { return ("未通电", 0, red) }
            guard let state else { return ("", nil, .clear) }
            switch state.status {
            case .running:  return (state.status.label, state.throttle, green)
            case .starved:  return (state.status.label, state.throttle, orange)
            case .blocked:  return (state.status.label, state.throttle, red)
            case .inactive, .noRecipe: return (state.status.label, state.throttle, .white.opacity(0.45))
            }
        }()
        if !label.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(label).font(.system(size: 11, weight: .bold)).foregroundColor(color)
                    if let ratio {
                        Text("\(Int((ratio * 100).rounded()))%")
                            .font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(color)
                    }
                    Spacer()
                }
                if let ratio {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Color.white.opacity(0.08))
                            Rectangle().fill(color).frame(width: geo.size.width * max(0, min(1, ratio)))
                        }
                    }
                    .frame(height: 4)
                }
                if placed.isActive, let detail = isUnpowered ? "不在任何供电桩范围内，不运行" : state?.detail {
                    Text(detail).font(.system(size: 10)).foregroundColor(.white.opacity(0.55))
                }
            }
        }
    }

    private var movingBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.tap.fill").foregroundColor(Color(red: 0.4, green: 0.7, blue: 0.9))
            Text(vm.moveFailedMessage ?? "点按网格上的目标位置（点的格子是建筑新的左上角），原来接的线不会跟着走")
                .font(.system(size: 10))
                .foregroundColor(vm.moveFailedMessage == nil ? .white.opacity(0.75) : red)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Color(red: 0.4, green: 0.7, blue: 0.9).opacity(0.12))
    }

    // MARK: - 主体：按建筑类型
    @ViewBuilder
    private var content: some View {
        if def.isMultiRecipeMachine {
            section("配方（可多选，自我供给）") { multiRecipePicker(for: def) }
        } else if !vm.availableRecipes(for: def).isEmpty {
            section("配方") { recipePicker(for: def) }
        }
        if let state, !state.needs.isEmpty {
            section("原料到货") { ingredientRows(state) }
        }
        if let state, let item = state.activatorItem ?? FlowSimulator.transmuterActivators[def.id] {
            section(def.id == "vaporizer_1" ? "进气" : "激活") { activatorRow(item: item, state: state) }
        }
        if let state, state.outputs.values.contains(where: { $0 > 1e-9 }) {
            section("产出") { rateRows(state.outputs, color: green) }
        }
        if def.id == BuildingDefinition.warehouseOutletID {
            section("取货材料") { outletMaterialPicker(for: def) }
        }
        if def.id == "log_conditioner" || def.id == "log_pipe_conditioner" {
            section("限速") { flowLimitControl(for: def) }
            section("只放行") { filterItemPicker(for: def) }
        }
        if def.isProtocolCore {
            section("协议核心") {
                infoText(String(format: "固定发电 %.0f MW，计入总发电；本身没有供电范围，周围建筑仍要靠供电桩。", def.powerGenerate))
            }
        }
        if def.id == "power_station_1" { generatorSection }
        if let range = def.powerRange { diffuserSection(range: range) }
        if let sink = vm.stats.sinkStates.first(where: { $0.id == placed.id }) {
            section(def.id == BuildingDefinition.warehouseInletID ? "入库" : "处理") {
                rateRows(sink.consumed, color: Color(red: 0.4, green: 0.7, blue: 0.9))
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ body: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.45))
            body()
        }
    }

    private func infoText(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundColor(.white.opacity(0.7))
            .fixedSize(horizontal: false, vertical: true)
    }

    /// 原料：到货 / 满载需求，到货不够的标橙
    private func ingredientRows(_ state: FlowSimulator.MachineState) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(state.needs.keys.sorted(), id: \.self) { item in
                let need = (state.needs[item] ?? 0) * 60
                let arrived = (state.arrivals[item] ?? 0) * 60
                let enough = arrived + 1e-6 >= need
                HStack(spacing: 6) {
                    ItemIcon(name: item, size: 20)
                    Text(item).font(.system(size: 12)).foregroundColor(.white.opacity(0.85))
                    Spacer()
                    Text(String(format: "%.1f / %.1f /min", arrived, need))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(enough ? green : orange)
                }
            }
        }
    }

    private func rateRows(_ rates: [String: Double], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(rates.filter { $0.value > 1e-9 }.keys.sorted(), id: \.self) { item in
                HStack(spacing: 6) {
                    ItemIcon(name: item, size: 20)
                    Text(item).font(.system(size: 12)).foregroundColor(.white.opacity(0.85))
                    Spacer()
                    Text(String(format: "%.1f /min", (rates[item] ?? 0) * 60))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(color)
                }
            }
        }
    }

    /// 转化机激活口 / 气体散布机进气口：最低 6/min
    private func activatorRow(item: String, state: FlowSimulator.MachineState) -> some View {
        let arrived = state.activatorArrival * 60
        let need = FlowSimulator.activatorNeed * 60
        let ok = arrived + 1e-6 >= need
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                ItemIcon(name: item, size: 20)
                Text(item).font(.system(size: 12)).foregroundColor(.white.opacity(0.85))
                Spacer()
                Text(String(format: "%.1f /min（需要 ≥%.0f）", arrived, need))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(ok ? green : red)
            }
            if def.id == "vaporizer_1" {
                infoText("惰气→稳定、水蒸气→潮湿、酸气→酸性、息壤气→息壤，影响周围 \(FlowSimulator.vaporizerRange) 格")
            }
        }
    }

    @ViewBuilder
    private var generatorSection: some View {
        let generator = vm.stats.generators.first { $0.id == placed.id }
        section("发电") {
            VStack(alignment: .leading, spacing: 4) {
                if let generator, let fuel = generator.fuel {
                    HStack(spacing: 6) {
                        ItemIcon(name: fuel, size: 20)
                        Text("正在烧 \(fuel)").font(.system(size: 12)).foregroundColor(.white.opacity(0.85))
                        Spacer()
                        Text(String(format: "%.0f MW", generator.power))
                            .font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundColor(yellow)
                    }
                    if generator.fuelRatio < 0.999 {
                        infoText(String(format: "燃料只送到满烧需要量的 %.0f%%，发电按比例打折", generator.fuelRatio * 100))
                    }
                } else {
                    infoText("没有燃料，不发电。接一条传送带送燃料进来：")
                }
                ForEach(FuelCatalog.all, id: \.itemId) { fuel in
                    Text(String(format: "%@  %.0f MW，每个烧 %.0f 秒", fuel.name, fuel.powerProvide, fuel.secondsPerItem))
                        .font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.5))
                }
            }
        }
    }

    private func diffuserSection(range: Int) -> some View {
        let covered = vm.layout.buildings.filter { other in
            guard other.id != placed.id, other.isActive, let d = BuildingDefinition.find(other.definitionID), d.needsPower else { return false }
            return Self.overlaps(placed, def, other, d, expandedBy: range)
        }.count
        return section("供电范围") {
            infoText("本体向四周各扩 \(range) 格（网格上虚线框），范围内有 \(covered) 台需要供电的建筑")
        }
    }

    private static func overlaps(_ a: PlacedBuilding, _ ad: BuildingDefinition,
                                 _ b: PlacedBuilding, _ bd: BuildingDefinition, expandedBy e: Int) -> Bool {
        let ac = a.occupiedCells(definition: ad), bc = b.occupiedCells(definition: bd)
        guard let ax0 = ac.map(\.col).min(), let ax1 = ac.map(\.col).max(),
              let ay0 = ac.map(\.row).min(), let ay1 = ac.map(\.row).max(),
              let bx0 = bc.map(\.col).min(), let bx1 = bc.map(\.col).max(),
              let by0 = bc.map(\.row).min(), let by1 = bc.map(\.row).max() else { return false }
        return ax1 + e >= bx0 && ax0 - e <= bx1 && ay1 + e >= by0 && ay0 - e <= by1
    }

    // MARK: - 按钮
    private func iconButton(_ icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 13, weight: .bold)).foregroundColor(color)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
    }

    private func actionButton(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 14))
                Text(title).font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(color)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(color.opacity(0.12))
            .overlay(Rectangle().stroke(color.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 配方 / 取货材料 / 限速（原来在 FactoryLayoutView 里）

    /// 配方选择：机器有真实配方数据才显示，选完立即重新计算产能统计
    @ViewBuilder
    private func recipePicker(for def: BuildingDefinition) -> some View {
        let recipes = vm.availableRecipes(for: def)
        if !recipes.isEmpty, let placedID = vm.selectedBuildingID {
            let currentID = vm.selectedPlaced?.selectedRecipeID
            let current = recipes.first { $0.id == currentID }
            Button {
                showRecipeSheet = true
            } label: {
                HStack(spacing: 4) {
                    if let output = current?.outputs.first {
                        ItemIcon(name: output.name, size: 20)
                    }
                    Label(
                    current?.outputs.first?.name ?? "配方一览",
                    systemImage: "list.bullet.rectangle"
                    )
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Color(red: 0.4, green: 0.8, blue: 0.2))
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showRecipeSheet) {
                SearchablePickerSheet(
                    title: "配方一览",
                    items: recipes.map { recipe in
                        let outputText = recipe.outputs.map { "\($0.name)×\($0.count)" }.joined(separator: " + ")
                        let inputText = recipe.inputs.map { "\($0.name)×\($0.count)" }.joined(separator: " + ")
                        return SearchablePickerItem(
                            id: recipe.id,
                            title: "\(outputText)（\(recipe.time)s）",
                            subtitle: recipeSubtitle(inputText: inputText, env: recipe.requiredEnv),
                            iconName: recipe.outputs.first?.name
                        )
                    },
                    selectedID: currentID,
                    clearTitle: "不设置配方",
                    onSelect: { id in
                        vm.selectRecipe(id, for: placedID)
                    },
                    filterChips: ingredientChips(for: recipes),
                    chipsLabel: "按原料筛选（跟游戏一样先选吃什么）"
                )
            }
        }
    }

    /// 反应池/扩容反应池：多选配方 + 自我供给分析 + 净产出的输出口手动指定
    @ViewBuilder
    private func multiRecipePicker(for def: BuildingDefinition) -> some View {
        let recipes = vm.availableRecipes(for: def)
        if !recipes.isEmpty, let placedID = vm.selectedBuildingID, let placed = vm.selectedPlaced {
            let selectedIDs = placed.selectedRecipeIDs
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    showRecipeSheet = true
                } label: {
                    Label(selectedIDs.isEmpty ? "配方一览（可多选）" : "已勾选 \(selectedIDs.count) 条配方",
                          systemImage: "list.bullet.rectangle.fill")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Color(red: 0.4, green: 0.8, blue: 0.2))
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showRecipeSheet) {
                    SearchablePickerSheet(
                        title: "配方一览",
                        items: recipes.map { recipe in
                            let outputText = recipe.outputs.map { "\($0.name)×\($0.count)" }.joined(separator: " + ")
                            let inputText = recipe.inputs.map { "\($0.name)×\($0.count)" }.joined(separator: " + ")
                            return SearchablePickerItem(
                                id: recipe.id,
                                title: "\(outputText)（\(recipe.time)s）",
                                subtitle: inputText.isEmpty ? nil : "原料：\(inputText)",
                                iconName: recipe.outputs.first?.name
                            )
                        },
                        multiSelect: true,
                        selectedIDs: selectedIDs,
                        onToggle: { id in
                            vm.toggleRecipe(id, for: placedID)
                        },
                        filterChips: ingredientChips(for: recipes),
                        chipsLabel: "按原料筛选（跟游戏一样先选吃什么，能多选配方）"
                    )
                }

                if let analysis = vm.selfSupplyAnalysis(for: placed, definition: def) {
                    selfSupplySummary(analysis, def: def, placedID: placedID)
                }
            }
        }
    }

    @ViewBuilder
    private func selfSupplySummary(_ analysis: FlowSimulator.SelfSupplyAnalysis, def: BuildingDefinition, placedID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let cap = def.multiRecipeItemCapacity {
                Text("涉及物品 \(analysis.totalDistinctItems)/\(cap) 种")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(analysis.exceedsCapacity ? .red : .white.opacity(0.5))
            }
            let internalItems = analysis.netItems.filter { abs($0.net) < 1e-9 }
            if !internalItems.isEmpty {
                HStack(spacing: 3) {
                    ForEach(internalItems, id: \.name) { item in
                        ItemIcon(name: item.name, size: 18)
                    }
                    Text("内部循环：\(internalItems.map { $0.name }.joined(separator: "、"))（不占外部口）")
                }
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Color(red: 0.4, green: 0.7, blue: 0.9))
            }
            if !analysis.externalInputs.isEmpty {
                let text = analysis.externalInputs
                    .map { "\($0.name) \(String(format: "%.0f", -$0.net * 60))/min" }
                    .joined(separator: "、")
                HStack(spacing: 3) {
                    ForEach(analysis.externalInputs, id: \.name) { item in
                        ItemIcon(name: item.name, size: 18)
                    }
                    Text("外部输入：\(text)")
                }
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
            }
            ForEach(analysis.externalOutputs, id: \.name) { output in
                outputAssignmentRow(item: output.name, rate: output.net, def: def, placedID: placedID)
            }
            if analysis.exceedsOutputCap {
                Text("对外输出超限：同时最多 2 种液体 + 1 种固体，多出来的必须靠另一条配方内部消化掉")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.red)
            }
        }
    }

    private func outputPortsOfKind(_ def: BuildingDefinition, isSolid: Bool) -> [Int] {
        let kind: PortKind = isSolid ? .item : .pipe
        return def.ports.enumerated()
            .filter { $0.element.ioDirection == .output && $0.element.kind == kind }
            .map { $0.offset }
    }

    /// 净产出的物品要不要手动指定输出口：只有同类型口有 2 个以上净产物时才需要选，只有 1 个净产物时用不着
    @ViewBuilder
    private func outputAssignmentRow(item: String, rate: Double, def: BuildingDefinition, placedID: UUID) -> some View {
        let isSolid = ItemCatalog.isSolid(item)
        let ports = outputPortsOfKind(def, isSolid: isSolid)
        HStack(spacing: 6) {
            ItemIcon(name: item, size: 18)
            Text("输出：\(item) \(String(format: "%.0f", rate * 60))/min")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
            if ports.count > 1 {
                let current = vm.selectedPlaced?.outputPortAssignments.first { $0.value == item }?.key
                ForEach(Array(ports.enumerated()), id: \.element) { seq, portIdx in
                    Button {
                        vm.setOutputPortAssignment(item: item, portIndex: portIdx, for: placedID)
                    } label: {
                        Text("口\(seq + 1)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(current == portIdx ? Color(red: 0.4, green: 0.8, blue: 0.2) : Color.white.opacity(0.12))
                            .foregroundColor(current == portIdx ? .black : .white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// 这批配方里出现过的所有原料名（去重），给"先选原料再看配方"这个筛选条用
    private func ingredientChips(for recipes: [Recipe]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for recipe in recipes {
            for input in recipe.inputs where !seen.contains(input.name) {
                seen.insert(input.name)
                ordered.append(input.name)
            }
        }
        return ordered
    }

    private func recipeSubtitle(inputText: String, env: String?) -> String? {
        var parts: [String] = []
        if !inputText.isEmpty { parts.append("原料：\(inputText)") }
        if let env { parts.append("需要\(env)环境") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// 物品准入口/管道准入口的限速：步长 6/min（游戏里滑条的步长），到带速/管速上限；关掉就是不额外限速
    @ViewBuilder
    private func flowLimitControl(for def: BuildingDefinition) -> some View {
        if def.id == "log_conditioner" || def.id == "log_pipe_conditioner",
           let placedID = vm.selectedBuildingID {
            let maxPerMin = (def.id == "log_pipe_conditioner" ? FlowSimulator.pipeCapacity : FlowSimulator.beltCapacity) * 60
            let current = vm.selectedPlaced?.flowLimitPerMin
            HStack(spacing: 8) {
                Image(systemName: "speedometer")
                    .font(.system(size: 10))
                Text(current.map { String(format: "限速 %.0f/min", $0) } ?? "不限速")
                    .font(.system(size: 10, design: .monospaced))
                Button {
                    vm.setFlowLimit(max((current ?? maxPerMin) - 6, 0), for: placedID)
                } label: { Image(systemName: "minus.circle") }
                Button {
                    let next = (current ?? maxPerMin) + 6
                    vm.setFlowLimit(next >= maxPerMin ? nil : next, for: placedID)
                } label: { Image(systemName: "plus.circle") }
            }
            .foregroundColor(Color(red: 0.4, green: 0.8, blue: 0.2))
            .buttonStyle(.plain)
        }
    }

    /// 物品/管道准入口只放行哪种物品：物品准入口从固体里选，管道准入口从液体和气体里选；不设置 = 全部通过
    @ViewBuilder
    private func filterItemPicker(for def: BuildingDefinition) -> some View {
        if let placedID = vm.selectedBuildingID {
            let current = vm.selectedPlaced?.filterItemID.flatMap(ItemCatalog.name(for:))
            let candidates = def.id == "log_pipe_conditioner" ? vm.fluidMaterials : vm.solidMaterials
            Button {
                showFilterSheet = true
            } label: {
                HStack(spacing: 4) {
                    if let current { ItemIcon(name: current, size: 20) }
                    Label(current ?? "全部通过", systemImage: "line.3.horizontal.decrease.circle")
                }
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color(red: 0.4, green: 0.8, blue: 0.2))
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showFilterSheet) {
                SearchablePickerSheet(
                    title: "只放行哪种物品",
                    items: candidates.map { SearchablePickerItem(id: $0.itemId, title: $0.name, iconName: $0.name) },
                    selectedID: vm.selectedPlaced?.filterItemID,
                    clearTitle: "全部通过",
                    onSelect: { item in
                        vm.setFilterItem(item, for: placedID)
                    }
                )
            }
            if current != nil {
                infoText("其它物品到这里会被挡住，上游跟着堵。")
            }
        }
    }

    /// 仓库取货口的材料选择：只对取货口显示（存货口是入口，接收任意材料，不用选），选完立即重新计算产能统计
    @ViewBuilder
    private func outletMaterialPicker(for def: BuildingDefinition) -> some View {
        if def.id == BuildingDefinition.warehouseOutletID, let placedID = vm.selectedBuildingID {
            let current = vm.selectedPlaced?.outletMaterialID.flatMap(ItemCatalog.name(for:))
            Button {
                showMaterialSheet = true
            } label: {
                HStack(spacing: 4) {
                    if let current { ItemIcon(name: current, size: 20) }
                    Label(current ?? "选择材料", systemImage: "shippingbox.fill")
                }
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color(red: 0.4, green: 0.8, blue: 0.2))
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showMaterialSheet) {
                SearchablePickerSheet(
                    title: "选择取货材料",
                    items: vm.solidMaterials.map { SearchablePickerItem(id: $0.itemId, title: $0.name, iconName: $0.name) },
                    selectedID: vm.selectedPlaced?.outletMaterialID,
                    clearTitle: "未设置",
                    onSelect: { material in
                        vm.setOutletMaterial(material, for: placedID)
                    }
                )
            }
        }
    }

}
