// Created by Jinjia Ou on 10/2/26.

import SwiftUI

/// 选中建筑的详情面板：iPad 放独立右侧栏，iPhone 放在网格下方（不是模态弹窗，展开时网格照样能点能拖）。
/// 头部是通用信息和操作（开关/移动/旋转/收纳），下面按建筑类型显示配方、到货、激活、发电等内容
struct BuildingDetailPanel: View {
    enum Style { case side, bottom }

    @ObservedObject var vm: FactoryViewModel
    let placed: PlacedBuilding
    let def: BuildingDefinition
    let style: Style
    var maxContentHeight: CGFloat = 300
    var maxPanelHeight: CGFloat? = nil

    @State private var expanded = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showRecipeSheet = false
    @State private var showMaterialSheet = false
    @State private var showFilterSheet = false
    /// 协议核心正在选材料的出货口（BuildingDefinition.ports 下标），nil = 没在选
    @State private var corePortSheetIndex: Int? = nil

    private let green = AppColors.success
    private let orange = AppColors.warning
    private let red = AppColors.error
    private let yellow = AppColors.accent

    private var state: FlowSimulator.MachineState? {
        vm.stats.machineStates.first { $0.id == placed.id }
    }
    private var isUnpowered: Bool { vm.stats.unpoweredIDs.contains(placed.id) }
    private var isMoving: Bool { vm.movingBuildingID == placed.id }

    var body: some View {
        AppInspectorContainer(title: def.displayName, subtitle: headerStatus,
                              placement: style == .side ? .side : .bottom,
                              isExpanded: $expanded,
                              maxContentHeight: style == .bottom ? maxContentHeight : nil,
                              maxPanelHeight: style == .bottom ? maxPanelHeight : nil,
                              summaryText: powerSummary,
                              disclosureTitle: def.isProtocolCore ? "出货口配置与运行详情" : "配置与运行详情",
                              onClose: {
                                  vm.cancelMoving()
                                  vm.selectedBuildingID = nil
                              }) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                statusBar
                if isMoving { movingBanner }
                content
            }
        } actions: {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: AppSpacing.xxs),
                                      count: dynamicTypeSize.isAccessibilitySize ? 2 : 4), spacing: AppSpacing.xxs) {
                actionButton(placed.isActive ? "关闭" : "开启", icon: "power",
                             color: placed.isActive ? green : AppColors.secondaryText) { vm.toggleActive(placed.id) }
                actionButton(isMoving ? "取消移动" : "移动", icon: "arrow.up.and.down.and.arrow.left.and.right",
                             color: AppColors.info) {
                    expanded = true
                    isMoving ? vm.cancelMoving() : vm.startMoving(placed.id)
                }
                actionButton("旋转", icon: "rotate.right", color: AppColors.accent) { vm.rotateSelected() }
                actionButton("收纳", icon: "tray.and.arrow.down.fill", color: red) { vm.deleteSelected() }
            }
        }
    }

    private var headerStatus: String {
        if vm.stats.mapConflicts[placed.id] != nil { return "地图不支持" }
        if !placed.isActive { return "已关闭" }
        if isUnpowered { return "未通电" }
        return state?.status.label ?? def.category.displayName
    }

    private var powerSummary: String {
        if def.powerUsage > 0 {
            return String(format: "耗电功率值 %.0f MW", def.powerUsage)
        } else if def.isProtocolCore {
            return String(format: "固定发电 %.0f MW · 本身无供电范围", def.powerGenerate)
        } else if def.powerRange != nil || def.id == "power_station_1" {
            return "电力设施"
        } else {
            return "不耗电"
        }
    }

    /// 状态条：关闭 / 未通电优先，其余看模拟结果的运行率
    @ViewBuilder
    private var statusBar: some View {
        let (label, ratio, color): (String, Double?, Color) = {
            if !placed.isActive { return ("已关闭", nil, AppColors.secondaryText) }
            if isUnpowered { return ("未通电", 0, red) }
            guard let state else { return ("", nil, .clear) }
            switch state.status {
            case .running:  return (state.status.label, state.throttle, green)
            case .starved:  return (state.status.label, state.throttle, orange)
            case .blocked:  return (state.status.label, state.throttle, red)
            case .inactive, .noRecipe: return (state.status.label, state.throttle, AppColors.secondaryText)
            }
        }()
        if !label.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(label).font(AppTypography.supporting).foregroundColor(color)
                    if let ratio {
                        Text("\(Int((ratio * 100).rounded()))%")
                            .font(AppTypography.supporting).foregroundColor(color)
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
                    Text(detail).font(AppTypography.supporting).foregroundColor(AppColors.secondaryText)
                }
            }
        }
    }

    private var movingBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.tap.fill").foregroundColor(AppColors.info)
            Text(vm.moveFailedMessage ?? "点按网格上的目标位置（点的格子是建筑新的左上角），已连接的线路会尝试重新连接，无法连接时会提示")
                .font(AppTypography.supporting)
                .foregroundColor(vm.moveFailedMessage == nil ? AppColors.primaryText : red)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(AppColors.info.opacity(0.12))
    }

    // MARK: - 主体：按建筑类型
    @ViewBuilder
    private var content: some View {
        if let conflict = vm.stats.mapConflicts[placed.id] {
            section("地图不支持") {
                Text("\(conflict)。这台建筑不参与产能计算。")
                    .font(AppTypography.supporting)
                    .foregroundColor(AppColors.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
        if def.choosesOutletMaterial {
            section(def.isUndergroundOutlet ? "出什么" : "取货材料") { outletMaterialPicker(for: def) }
        }
        if def.id == "log_conditioner" || def.id == "log_pipe_conditioner" {
            section("限速") { flowLimitControl(for: def) }
            section("只放行") { filterItemPicker(for: def) }
        }
        if def.isProtocolCore {
            section("出货口") { corePortPicker(for: def) }
            section("协议核心") {
                infoText(String(format: "固定发电 %.0f MW，计入总发电；本身没有供电范围，周围建筑仍要靠供电桩。", def.powerGenerate))
                infoText("进货口送进来的东西全部入库。")
            }
        }
        if def.id == "power_station_1" { generatorSection }
        if let range = def.powerRange { diffuserSection(range: range) }
        if let sink = vm.stats.sinkStates.first(where: { $0.id == placed.id }) {
            section(def.id == BuildingDefinition.warehouseInletID || def.isProtocolCore ? "入库" : def.isUndergroundInlet ? "送入暗管" : "处理") {
                rateRows(sink.consumed, color: AppColors.info)
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ body: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AppTypography.supporting)
                .foregroundColor(AppColors.secondaryText)
            body()
        }
    }

    private func infoText(_ text: String) -> some View {
        Text(text).font(AppTypography.supporting).foregroundColor(AppColors.primaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// 原料：到货 / 满载需求，到货不够的标橙
    private func ingredientRows(_ state: FlowSimulator.MachineState) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(state.needs.keys.sorted(), id: \.self) { item in
                let need = (state.needs[item] ?? 0) * 60
                let arrived = (state.arrivals[item] ?? 0) * 60
                let enough = arrived + 1e-6 >= need
                HStack(alignment: .top, spacing: AppSpacing.xs) {
                    ItemIcon(name: item, size: AppSize.icon)
                    AppKeyValueRow(title: item, value: String(format: "%.1f / %.1f /min", arrived, need),
                                   detail: enough ? "到货 / 需求" : "到货 / 需求 · 原料不足",
                                   valueColor: enough ? green : orange)
                }
            }
        }
    }

    private func rateRows(_ rates: [String: Double], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(rates.filter { $0.value > 1e-9 }.keys.sorted(), id: \.self) { item in
                HStack(alignment: .top, spacing: AppSpacing.xs) {
                    ItemIcon(name: item, size: AppSize.icon)
                    AppKeyValueRow(title: item, value: String(format: "%.1f /min", (rates[item] ?? 0) * 60),
                                   valueColor: color)
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
            HStack(alignment: .top, spacing: AppSpacing.xs) {
                ItemIcon(name: item, size: AppSize.icon)
                AppKeyValueRow(title: item, value: String(format: "%.1f /min（需要 ≥%.0f）", arrived, need),
                               detail: ok ? nil : "激活材料不足", valueColor: ok ? green : red)
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
                        Text("正在烧 \(DisplayName.item(fuel))").font(AppTypography.rowTitle).foregroundColor(AppColors.primaryText)
                        Spacer()
                        Text(String(format: "%.0f MW", generator.power))
                            .font(AppTypography.supporting).foregroundColor(yellow)
                    }
                    if generator.fuelRatio < 0.999 {
                        infoText(String(format: "燃料只送到满烧需要量的 %.0f%%，发电按比例打折", generator.fuelRatio * 100))
                    }
                } else {
                    infoText("没有燃料，不发电。接一条传送带送燃料进来：")
                }
                ForEach(FuelCatalog.all, id: \.itemId) { fuel in
                    Text(String(format: "%@  %.0f MW，每个烧 %.0f 秒", DisplayName.item(fuel.name), fuel.powerProvide, fuel.secondsPerItem))
                        .font(AppTypography.supporting).foregroundColor(AppColors.secondaryText)
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
    private func actionButton(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: AppSpacing.xxs) {
                Image(systemName: icon).foregroundStyle(color).font(AppTypography.supporting)
                Text(title).foregroundStyle(AppColors.primaryText).font(AppTypography.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, AppSpacing.xxs)
            .frame(maxWidth: .infinity, minHeight: AppSize.touchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
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
                    current?.outputs.first.map { DisplayName.item($0.name) } ?? String(localized: "配方一览"),
                    systemImage: "list.bullet.rectangle"
                    )
                }
                .font(AppTypography.supporting)
                .foregroundColor(AppColors.success)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showRecipeSheet) {
                SearchablePickerSheet(
                    title: "配方一览",
                    items: recipes.map { recipe in
                        let outputText = recipe.outputs.map { "\(DisplayName.item($0.name))×\($0.count)" }.joined(separator: " + ")
                        let inputText = recipe.inputs.map { "\(DisplayName.item($0.name))×\($0.count)" }.joined(separator: " + ")
                        return SearchablePickerItem(
                            id: recipe.id,
                            title: "\(outputText)（\(recipe.time)s）",
                            subtitle: recipeSubtitle(inputText: inputText, env: recipe.requiredEnv),
                            iconName: recipe.outputs.first?.name,
                            disabledTag: recipeMapTag(recipe, def: def)
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

    /// 这条配方在当前地图不能用时的标签（"仅武陵"），能用返回 nil
    private func recipeMapTag(_ recipe: Recipe, def: BuildingDefinition) -> String? {
        guard vm.layout.mapType.rules.blockedMode(of: recipe, on: def) != nil else { return nil }
        let maps = MapRules.maps(allowing: recipe, on: def).map(\.displayName).joined(separator: "、")
        return "仅\(maps)"
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
                        .font(AppTypography.supporting)
                        .foregroundColor(AppColors.success)
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showRecipeSheet) {
                    SearchablePickerSheet(
                        title: "配方一览",
                        items: recipes.map { recipe in
                            let outputText = recipe.outputs.map { "\(DisplayName.item($0.name))×\($0.count)" }.joined(separator: " + ")
                            let inputText = recipe.inputs.map { "\(DisplayName.item($0.name))×\($0.count)" }.joined(separator: " + ")
                            return SearchablePickerItem(
                                id: recipe.id,
                                title: "\(outputText)（\(recipe.time)s）",
                                subtitle: inputText.isEmpty ? nil : "原料：\(inputText)",
                                iconName: recipe.outputs.first?.name,
                                disabledTag: recipeMapTag(recipe, def: def)
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
                    .font(AppTypography.supporting)
                    .foregroundColor(analysis.exceedsCapacity ? .red : AppColors.secondaryText)
            }
            let internalItems = analysis.netItems.filter { abs($0.net) < 1e-9 }
            if !internalItems.isEmpty {
                HStack(spacing: 3) {
                    ForEach(internalItems, id: \.name) { item in
                        ItemIcon(name: item.name, size: 18)
                    }
                    Text("内部循环：\(internalItems.map { DisplayName.item($0.name) }.joined(separator: "、"))（不占外部口）")
                }
                    .font(AppTypography.supporting)
                    .foregroundColor(AppColors.info)
            }
            if !analysis.externalInputs.isEmpty {
                let text = analysis.externalInputs
                    .map { "\(DisplayName.item($0.name)) \(String(format: "%.0f", -$0.net * 60))/min" }
                    .joined(separator: "、")
                HStack(spacing: 3) {
                    ForEach(analysis.externalInputs, id: \.name) { item in
                        ItemIcon(name: item.name, size: 18)
                    }
                    Text("外部输入：\(text)")
                }
                    .font(AppTypography.supporting)
                    .foregroundColor(AppColors.secondaryText)
            }
            ForEach(analysis.externalOutputs, id: \.name) { output in
                outputAssignmentRow(item: output.name, rate: output.net, def: def, placedID: placedID)
            }
            if analysis.exceedsOutputCap {
                Text("对外输出超限：同时最多 2 种液体 + 1 种固体，多出来的必须靠另一条配方内部消化掉")
                    .font(AppTypography.supporting)
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
            Text("输出：\(DisplayName.item(item)) \(String(format: "%.0f", rate * 60))/min")
                .font(AppTypography.supporting)
                .foregroundColor(AppColors.primaryText)
            if ports.count > 1 {
                let current = vm.selectedPlaced?.outputPortAssignments.first { $0.value == item }?.key
                ForEach(Array(ports.enumerated()), id: \.element) { seq, portIdx in
                    Button {
                        vm.setOutputPortAssignment(item: item, portIndex: portIdx, for: placedID)
                    } label: {
                        Text("口\(seq + 1)")
                            .font(AppTypography.supporting)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(current == portIdx ? AppColors.success : Color.white.opacity(0.12))
                            .foregroundColor(current == portIdx ? .black : AppColors.secondaryText)
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
        if let env { parts.append("需要\(DisplayName.environment(env + "环境"))") }
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
                    .font(AppTypography.supporting)
                Text(current.map { String(format: "限速 %.0f/min", $0) } ?? "不限速")
                    .font(AppTypography.supporting)
                Button {
                    vm.setFlowLimit(max((current ?? maxPerMin) - 6, 0), for: placedID)
                } label: { Image(systemName: "minus.circle") }
                Button {
                    let next = (current ?? maxPerMin) + 6
                    vm.setFlowLimit(next >= maxPerMin ? nil : next, for: placedID)
                } label: { Image(systemName: "plus.circle") }
            }
            .foregroundColor(AppColors.success)
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
                    Label(current.map(DisplayName.item) ?? String(localized: "全部通过"), systemImage: "line.3.horizontal.decrease.circle")
                }
                    .font(AppTypography.supporting)
                    .foregroundColor(AppColors.success)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showFilterSheet) {
                SearchablePickerSheet(
                    title: "只放行哪种物品",
                    items: candidates.map { SearchablePickerItem(id: $0.itemId, title: DisplayName.item($0.name), iconName: $0.name) },
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

    /// 协议核心的出货口：每个口单独选出什么固体，按带速出货；不设置的口不出货。
    /// 口的名字按实际朝向和位置排（比如"右 1"是右边从上往下第一个），跟着建筑旋转走
    @ViewBuilder
    private func corePortPicker(for def: BuildingDefinition) -> some View {
        if let placedID = vm.selectedBuildingID, let current = vm.selectedPlaced {
            let ports = corePortLabels(def: def, placed: current)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(ports, id: \.index) { port in
                    let material = current.portMaterialIDs[port.index].flatMap(ItemCatalog.name(for:))
                    Button {
                        corePortSheetIndex = port.index
                    } label: {
                        // 每行至少 44pt 高、整行可点，手机上不容易点错行
                        HStack(alignment: .center, spacing: AppSpacing.xs) {
                            Text(port.label)
                                .font(AppTypography.rowTitle)
                                .foregroundColor(AppColors.primaryText)
                                .fixedSize(horizontal: true, vertical: true)
                            if let material { ItemIcon(name: material, size: 24) }
                            Text(verbatim: material.map(DisplayName.item) ?? String(localized: "不出货"))
                                .font(AppTypography.rowTitle)
                                .fixedSize(horizontal: false, vertical: true)
                                .foregroundColor(material == nil ? AppColors.secondaryText : AppColors.success)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(AppTypography.rowTitle)
                                .foregroundColor(AppColors.secondaryText)
                        }
                        .padding(.vertical, AppSpacing.xxs)
                        .frame(minHeight: AppSize.touchTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(port.label)，\(material.map(DisplayName.item) ?? String(localized: "不出货"))")
                    .accessibilityHint("选择该出货口的材料")
                    Divider().overlay(AppColors.border)
                }
            }
            .sheet(isPresented: Binding(get: { corePortSheetIndex != nil },
                                        set: { if !$0 { corePortSheetIndex = nil } })) {
                if let portIndex = corePortSheetIndex {
                    SearchablePickerSheet(
                        title: "\(ports.first { $0.index == portIndex }?.label ?? "出货口") 出什么",
                        items: vm.solidMaterials.map { SearchablePickerItem(id: $0.itemId, title: DisplayName.item($0.name), iconName: $0.name) },
                        selectedID: current.portMaterialIDs[portIndex],
                        clearTitle: "不出货",
                        onSelect: { material in
                            vm.setPortMaterial(material, portIndex: portIndex, for: placedID)
                        }
                    )
                }
            }
        }
    }

    /// 协议核心出货口的显示名：按朝向分组（上/右/下/左），组内左右边从上往下、上下边从左往右编号
    private func corePortLabels(def: BuildingDefinition, placed: PlacedBuilding) -> [(index: Int, label: String)] {
        let sideNames: [BuildingRotation: String] = [.up: "上", .right: "右", .down: "下", .left: "左"]
        let outputs = def.ports.enumerated().filter { $0.element.ioDirection == .output }.map { item in
            (index: item.offset, resolved: item.element.resolvedPosition(placed: placed, definition: def))
        }
        var labels: [(index: Int, label: String)] = []
        for side in BuildingRotation.allCases {
            let onSide = outputs.filter { $0.resolved.facing == side }.sorted {
                side == .up || side == .down ? $0.resolved.cell.col < $1.resolved.cell.col
                                             : $0.resolved.cell.row < $1.resolved.cell.row
            }
            for (n, port) in onSide.enumerated() {
                labels.append((port.index, "\(sideNames[side] ?? "") \(n + 1)"))
            }
        }
        return labels
    }

    /// 仓库取货口（选固体）/暗管出口（选液体和气体）的材料选择：存货口、暗管入口是入口，接收任意材料，不用选；
    /// 选完立即重新计算产能统计
    @ViewBuilder
    private func outletMaterialPicker(for def: BuildingDefinition) -> some View {
        if def.choosesOutletMaterial, let placedID = vm.selectedBuildingID {
            let current = vm.selectedPlaced?.outletMaterialID.flatMap(ItemCatalog.name(for:))
            let candidates = def.isUndergroundOutlet ? vm.fluidMaterials : vm.solidMaterials
            Button {
                showMaterialSheet = true
            } label: {
                HStack(spacing: 4) {
                    if let current { ItemIcon(name: current, size: 20) }
                    Label(current.map(DisplayName.item) ?? String(localized: "选择材料"), systemImage: "shippingbox.fill")
                }
                    .font(AppTypography.supporting)
                    .foregroundColor(AppColors.success)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showMaterialSheet) {
                SearchablePickerSheet(
                    title: def.isUndergroundOutlet ? "暗管出口出什么" : "选择取货材料",
                    items: candidates.map { SearchablePickerItem(id: $0.itemId, title: DisplayName.item($0.name), iconName: $0.name) },
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
