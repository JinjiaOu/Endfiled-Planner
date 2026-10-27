import Foundation
let vm = RecipeViewModel()
var results: [String: Any] = [:]
for preset in ["preset_valley4_battery", "preset_wuling_equip"] {
    let data = try Data(contentsOf: DataPackStore.root.appendingPathComponent(preset + ".json"))
    let layout = try JSONDecoder().decode(FactoryLayout.self, from: data)
    // Round trip an existing Chinese save, including all Chinese dictionary keys.
    let encoded = try JSONEncoder().encode(layout)
    let restored = try JSONDecoder().decode(FactoryLayout.self, from: encoded)
    precondition(restored.mapType.rawValue == layout.mapType.rawValue)
    let stats = FactoryGridModel.analyze(layout: restored, machineRecipes: vm.recipesByMachine())
    results[preset] = ["map": restored.mapType.rawValue, "buildingCount": stats.buildingCount,
        "powerConsumed": stats.totalPowerConsumed, "powerGenerated": stats.totalPowerGenerated,
        "unpowered": stats.unpoweredCount, "converged": stats.flowConverged,
        "outputs": Dictionary(stats.productionLines.map { ($0.output, $0.ratePerMin) }, uniquingKeysWith: +),
        "consumption": Dictionary(stats.consumptionLines.map { ($0.output, $0.ratePerMin) }, uniquingKeysWith: +)]
}
let result = ProductionCalculator.calculate(target: "灼铜装备原件", ratePerMin: 6, recipes: vm.recipes, recipeChoice: [:], rawOverride: [:])
results["calculator"] = ["totalMachines": result.totalMachines, "powerMW": result.powerMW,
    "steps": result.steps.map { ["item": $0.item, "recipe": $0.recipe.id, "machines": $0.machines, "count": $0.machineCount] as [String: Any] }]
let hasEnglishNames = DataPackStore.decode([String: [String: String]].self, resource: "names_en") != nil
precondition(DisplayName.matches("灼铜装备原件", query: "Pyrrolite") == hasEnglishNames)
precondition(DisplayName.matches("灼铜装备原件", query: "灼铜"))
precondition(ItemCatalog.byName["灼铜装备原件"] != nil)
precondition(DisplayName.item("unknown") == "unknown")
if DisplayName.isEnglish && hasEnglishNames { precondition(DisplayName.item("灼铜装备原件") == "Pyrrolite Component") }
else { precondition(DisplayName.item("灼铜装备原件") == "灼铜装备原件") }
let output = try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
try output.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
print("language=\(Locale.preferredLanguages), english=\(DisplayName.isEnglish), machines=\(result.totalMachines), power=\(result.powerMW)")

precondition(MapType.valley4.rawValue == "四号谷地")
precondition(MapType.valley4.displayName == (DisplayName.isEnglish ? "Valley IV" : "四号谷地"))
precondition(FlowSimulator.MachineStatus.running.displayLabel == (DisplayName.isEnglish ? "Producing" : "生产中"))
for count in [1, 2] {
    let text = String(localized: "\(count) 个蓝图")
    let expected = DisplayName.isEnglish ? "\(count) \(count == 1 ? "blueprint" : "blueprints")" : "\(count) 个蓝图"
    precondition(text == expected, "Plural translation: \(text)")
}
let limit = 5, remaining = 1
let feedback = String(localized: "每天最多发 \(limit) 条，今天还能发 \(remaining) 条。")
precondition(feedback == (DisplayName.isEnglish ? "Up to 5 reports per day; 1 report remaining today." : "每天最多发 5 条，今天还能发 1 条。"), "Feedback plural: \(feedback)")
