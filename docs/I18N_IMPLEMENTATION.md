# EndfiledPlanner 中英双语交付说明

分支：`codex/i18n`。跟随系统语言，无 App 内语言开关。中文为开发语言和默认回退语言。

## 分阶段改动

### 阶段 1：官方游戏数据英文名

提交 `a2c289f`：生成独立的 `names_en.json`，更新在线清单；新增 `DisplayName`，在显示边界按 ID 取官方英文。图标、搜索选中值、配方分组和统计字典仍使用中文。

- 来源：`/Users/owen/Desktop/Project/EndfieldData/TableCfg/I18nTextTable_EN.json`。
- 顶层及各类 ID 均按字符串排序；UTF-8、`ensure_ascii=False`、LF、固定缩进。
- `names_en.json` 走 `DataPackStore.decode`，下载包优先、安装包回退；缺失/损坏时显示中文。
- 当前 App 使用的 245 个物品、78 个设备和 10 个分类全部有英文名；额外保留了源表其他物品的英文映射。
- 原有 schema-1 JSON 未加字段、未改结构。首次增加英文名不会改变原有 `datapack_meta.json`；清单内容指纹仍会更新。
- 带环境后缀的机器名按 `machineId` 翻译建筑，再翻译环境后缀。
- 物品搜索和材料/配方选择同时支持中英文，结果 ID 和 `ItemIcon.name` 仍是原始中文或物品 ID。

文件清单：
- `EndfiledPlanner/Calculator/ProductionCalculatorView.swift`
- `EndfiledPlanner/DesignSystem/Components/AppActions.swift`
- `EndfiledPlanner/DesignSystem/Components/AppMetricViews.swift`
- `EndfiledPlanner/DesignSystem/Components/AppSelection.swift`
- `EndfiledPlanner/DesignSystem/Components/AppStatusViews.swift`
- `EndfiledPlanner/DesignSystem/Components/AppSurface.swift`
- `EndfiledPlanner/ProductionOptimizer/View/BeltDetailPanel.swift`
- `EndfiledPlanner/ProductionOptimizer/View/BuildingDetailPanel.swift`
- `EndfiledPlanner/ProductionOptimizer/View/FactoryGridView.swift`
- `EndfiledPlanner/ProductionOptimizer/View/FactoryLayoutView.swift`
- `EndfiledPlanner/ProductionOptimizer/View/FactoryStatsView.swift`
- `EndfiledPlanner/ProductionOptimizer/View/SearchablePickerSheet.swift`
- `EndfiledPlanner/ProductionOptimizer/ViewModel/FactoryGridModel.swift`
- `EndfiledPlanner/ProductionOptimizer/ViewModel/FactoryViewModel+Placement.swift`
- `EndfiledPlanner/RecipeSearch/Model/DisplayName.swift`
- `EndfiledPlanner/RecipeSearch/View/NodeView.swift`
- `EndfiledPlanner/RecipeSearch/View/RecipeDetailView.swift`
- `EndfiledPlanner/RecipeSearch/View/RecipeDiagramComponents.swift`
- `EndfiledPlanner/RecipeSearch/View/RecipeFlowView.swift`
- `EndfiledPlanner/RecipeSearch/View/SearchView.swift`
- `EndfiledPlanner/other/datapack_manifest.json`
- `EndfiledPlanner/other/names_en.json`
- `Tools/gen_datapack.py`
- `Tools/gen_manifest.py`

### 阶段 2：String Catalog 和界面文案

提交 `54bf02e`、`c53e61d`：新增中文源语言 String Catalog；界面变量、数组、工具栏、提示、错误、无障碍描述等使用 `String(localized:)`。地图和反馈分类的 rawValue 保持不变，新增显示入口。模拟状态及诊断在显示边界转换，`FlowSimulator.swift` 保持原文件不变。

复核时保留了社区地图筛选的“全部”哨兵，以及跨地图警告聚合的原始中文键；仅翻译显示结果。English/zh-Hans 已写入工程设置。

文件清单：
- `EndfiledPlanner.xcodeproj/project.pbxproj`
- `EndfiledPlanner/BluePrint/View/BlueprintDisclaimerView.swift`
- `EndfiledPlanner/BluePrint/View/BlueprintSetCard.swift`
- `EndfiledPlanner/BluePrint/View/BlueprintSetDetailView.swift`
- `EndfiledPlanner/BluePrint/View/BlueprintSetView.swift`
- `EndfiledPlanner/BluePrint/ViewModel/BlueprintSetService.swift`
- `EndfiledPlanner/BluePrint/ViewModel/BlueprintSetViewModel.swift`
- `EndfiledPlanner/Calculator/ProductionCalculatorView.swift`
- `EndfiledPlanner/DataPack/DataPackUpdater.swift`
- `EndfiledPlanner/DataPack/DataUpdateBanner.swift`
- `EndfiledPlanner/DesignSystem/Components/AppInspectorContainer.swift`
- `EndfiledPlanner/DesignSystem/Components/AppSelection.swift`
- `EndfiledPlanner/ProductionOptimizer/ProductionOptimizerView.swift`
- `EndfiledPlanner/ProductionOptimizer/View/BeltDetailPanel.swift`
- `EndfiledPlanner/ProductionOptimizer/View/BuildingDetailPanel.swift`
- `EndfiledPlanner/ProductionOptimizer/View/FactoryGridView.swift`
- `EndfiledPlanner/ProductionOptimizer/View/FactoryGuideView.swift`
- `EndfiledPlanner/ProductionOptimizer/View/FactoryLayoutView.swift`
- `EndfiledPlanner/ProductionOptimizer/View/FactoryStatsView.swift`
- `EndfiledPlanner/ProductionOptimizer/View/FactoryWorkspaceToolbar.swift`
- `EndfiledPlanner/ProductionOptimizer/View/GroupSelectionPanel.swift`
- `EndfiledPlanner/ProductionOptimizer/View/MyLayoutsView.swift`
- `EndfiledPlanner/ProductionOptimizer/View/OptimizerDisclaimer.swift`
- `EndfiledPlanner/ProductionOptimizer/View/PlacementPanel.swift`
- `EndfiledPlanner/ProductionOptimizer/View/SearchablePickerSheet.swift`
- `EndfiledPlanner/ProductionOptimizer/ViewModel/FactoryBuilding.swift`
- `EndfiledPlanner/ProductionOptimizer/ViewModel/FactoryGridModel.swift`
- `EndfiledPlanner/ProductionOptimizer/ViewModel/FactoryPreset.swift`
- `EndfiledPlanner/ProductionOptimizer/ViewModel/FactoryViewModel+Group.swift`
- `EndfiledPlanner/ProductionOptimizer/ViewModel/FactoryViewModel+Placement.swift`
- `EndfiledPlanner/ProductionOptimizer/ViewModel/FactoryViewModel.swift`
- `EndfiledPlanner/RecipeSearch/Model/DisplayName.swift`
- `EndfiledPlanner/RecipeSearch/View/RecipeDetailView.swift`
- `EndfiledPlanner/RecipeSearch/View/RecipeDiagramComponents.swift`
- `EndfiledPlanner/RecipeSearch/View/SearchView.swift`
- `EndfiledPlanner/other/FeedbackView.swift`
- `EndfiledPlanner/other/HomeView.swift`
- `EndfiledPlanner/other/Localizable.xcstrings`
- `EndfiledPlanner/other/SettingsView.swift`

### 阶段 3：长文本、窄屏修正和验收

完整翻译基建使用指南、基建/蓝图/配方免责声明、预设载入说明、反馈与计算说明。目录最终有 574 个条目；数量相关句子采用英语单复数规则，多个数量使用目录 substitutions。

iPhone SE 实测发现画布英文建筑名截断，已给受限的画布/配方节点标签添加缩放；建筑面板与通用详情保留多行显示。新增可重跑的验收脚本和 Swift 模型验证程序。

文件清单：
- `EndfiledPlanner/BluePrint/View/BlueprintDisclaimerView.swift`
- `EndfiledPlanner/Calculator/ProductionCalculatorView.swift`
- `EndfiledPlanner/ProductionOptimizer/View/BuildingDetailPanel.swift`
- `EndfiledPlanner/ProductionOptimizer/View/FactoryGridView.swift`
- `EndfiledPlanner/ProductionOptimizer/View/FactoryGuideView.swift`
- `EndfiledPlanner/ProductionOptimizer/View/FactoryStatsView.swift`
- `EndfiledPlanner/ProductionOptimizer/View/GroupSelectionPanel.swift`
- `EndfiledPlanner/ProductionOptimizer/View/OptimizerDisclaimer.swift`
- `EndfiledPlanner/ProductionOptimizer/ViewModel/FactoryPreset.swift`
- `EndfiledPlanner/RecipeSearch/View/RecipeDiagramComponents.swift`
- `EndfiledPlanner/RecipeSearch/View/RecipeFlowView.swift`
- `EndfiledPlanner/RecipeSearch/View/SearchView.swift`
- `EndfiledPlanner/other/FeedbackView.swift`
- `EndfiledPlanner/other/Localizable.xcstrings`
- `Tools/i18n_checks/DataPackStore.swift`
- `Tools/i18n_checks/main.swift`
- `Tools/verify_i18n.py`
- `docs/I18N_IMPLEMENTATION.md`

## 故意保留的中文字符串及原因

- `items/devices/recipes/fuels.json` 中的中文名，以及 `Recipe.inputs/outputs.name`、`Recipe.machine`、`gasEnvName`、`requiredEnv`：它们参与配方分组、字典访问、模拟判断。翻译只用于旁边显示的文字。
- `FlowSimulator.swift` 全文件：气体、激活材料、废水接受集合、限制物品、模拟诊断的原始文本都未改。另设显示转换，不把翻译结果写回模拟器。
- `RecipeViewModel.isMiningMachine` 和配方图标选择中的“矿机 / 水泵 / 采种机 / 种植机 / 精炼 / 装配 / 粉碎 / 封装”等匹配文本：仍按原中文名判断。
- `BuildingCategory`、`MapType` 的 rawValue，`BuildingParser.categoryMap`：属于 Codable 值或数据解析映射。地图显示翻译为 Valley IV / Wuling。
- 社区筛选中的“全部”：比较用的哨兵，显示时单独翻译为 All；过滤传回原中文区域名。
- 跨地图警告聚合字典：仍按原始中文原因计数、排序，另存显示文本。
- `ProductionStats` 的物品键及 `outletMaterials` 的“未设置”哨兵：原样保留，仅显示时翻译。
- `MyLayouts.swift` 中“我的布局 N”“未命名布局”：会参与重名比较并存进布局，按约束保留。既有布局/用户命名也不翻译。
- 所有 `@AppStorage` / `UserDefaults` key、存档字段、预设 JSON、迁移索引、`Tools/presetlib.py` / `gen_presets.py` / `preset_wuling.py` 的中文：均未修改。
- CloudKit `category` 字段仍保存中文分类；`FeedbackInfo.dataVersion` 写入 CloudKit 的“内置 / 已更新”也维持原值。反馈页使用独立显示属性翻译这些文字。
- 社区蓝图的标题、说明、作者、备注、分享码与地点文本：作者内容原样展示；只翻译 UI 包装及“四号谷地 / 武陵”的区域显示。`blueprints.json` 未改。
- 调试日志、Preview 中的样例内容、仅预览使用的 DesignSystemGallery：不属于发布界面文案，原样保留。
- 设置页已有的 ABOUT / GAME DATA / VERSION / SETTINGS / GitHub 等英文：两种语言下统一沿用，符合交接文档允许的范围。

## 术语核对与待确认项

已从解包表核对的示例：

| 中文 | 官方英文 |
|---|---|
| 灼铜装备原件 | Pyrrolite Component |
| 高容谷地电池 | HC Valley Battery |
| 协议核心 | Automation-Core |
| 热能池 | Thermal Bank |
| 废水处理机 | Water Treatment Unit |
| 气体散布机 | Gas Dispersing Unit |
| 仓库存取线源桩 / 基段 | Depot Bus Port / Depot Bus Section |
| 暗管入口 / 出口 | Conduit Inlet / Conduit Outlet |
| 惰气 / 水蒸气 / 酸气 / 息壤气 | Inergen / Aquagen / Acridgen / Xiragen |
| 稳定环境 / 酸性环境 / 息壤环境 | Stable ENV / Acrid ENV / Xiranite ENV |

待你确认的显示用语（均不影响逻辑）：

1. “四号谷地小基地 / 武陵小基地”暂用 **Valley IV Outpost / Wuling Outpost**。这是 App 合并多处分基地的名称，未找到与这两个完整中文标签逐字对应的官方条目；也可改成 Small Base。
2. 装液/装气容器的显示名按 **Container (Content)** 组合，以对应 App 自行组合的“容器（已盛装内容）”。容器和内容分别使用官方英文，组合格式属于 App 文案。

“潮湿 / 潮湿环境”是现有工具的逻辑用词，官方表对应“湿润 / 湿润环境”译为 **Humid / Humid ENV**。只适配英文显示，原逻辑词未改。

## 验收结果

- `xcodebuild` Debug / iOS Simulator 编译通过（arm64；第一阶段也编译了 x86_64）。关闭签名进行本地编译。
- `python3 Tools/gen_datapack.py`、`python3 Tools/gen_presets.py` 均通过。与 `main` 比较，10 个既有非 Asset Catalog JSON 逐字节未变；只有新增 `names_en.json` 和 `datapack_manifest.json` 存在数据包差异。
- 英文名表重复生成逐字节一致，无 CRLF；清单 SHA-256/size 检查通过。
- `python3 Tools/verify_i18n.py --runtime` 通过：直接编译项目的原始 Swift 模型/计算器/模拟器，只用测试 DataPackStore 从指定目录读数据；测试 bundle 使用真实 String Catalog 编译产物。
- 分别以 `-AppleLanguages (zh-Hans)` 和 `(en)` 启动模型测试，两个预设的全部产出/消耗及功率统计逐字节一致；也与 `main` 原始代码编译后的中文基线逐字节一致。
- 旧的中文预设布局读取、编码、再次读取后，中文地图 rawValue 保持不变；英文显示入口正确返回 Valley IV；英文名文件完全缺失时仍回退中文且统计不变。
- 单数/复数、本地化插值、地图显示名、中英文搜索匹配和未知名字回退检查通过。

| 场景 | 建筑数 | 耗电 | 发电 | 目标产出 |
|---|---:|---:|---:|---:|
| 四号谷地电池预设（两种语言相同） | 56 | 400 MW | 420 MW | 高容谷地电池 6/min |
| 武陵装备预设（两种语言相同） | 185 | 1270 MW | 1300 MW | 灼铜装备原件 6/min |
| 灼铜装备原件 6/min 默认计算（两种语言相同） | 90 台机器 | 2080 MW | — | 6/min |

两个预设均收敛、无未供电建筑。

已在 iOS 26.2 / iPhone SE 3（375pt）实测英文首页、物品选择页、基建工具栏、建造分类/卡片、长免责声明与画布建筑名；修复了画布名称的省略。界面自动化对部分导航栏/搜索框的坐标操作不可用，因此未把所有页面的交互路径标成已逐项实测；搜索逻辑由运行时断言覆盖。

仍建议你最终手测：中文界面与原版逐页对照、真实旧用户存档跨语言打开、完整配方选择/指南/反馈页、在线下载包更新，以及 iPad 分屏与较大系统字号。CloudKit 实际发送没有执行。

## Xcode 手动设置 / 最终操作

不需要再手工添加 English：工程已设置 `developmentRegion = zh-Hans`，`knownRegions = zh-Hans / en / Base`。`Localizable.xcstrings` 和 `names_en.json` 位于同步文件夹内，编译已确认包含 en/zh-Hans 资源。

- 打开工程后检查 Project → Info → Localizations 显示 Chinese (Simplified) 与 English。
- 用 Scheme → Run → Options → App Language 分别选 English / Chinese (Simplified) 验证；正式运行仍跟随系统语言。
- 在真机/你的签名环境编译，做上述最终手测。存档无需迁移。
- `STRING_CATALOG_GENERATE_SYMBOLS` 已设为 NO：本项目使用 `String(localized:)`，目录包含纯数字/占位符 key，无需生成 Swift 符号。
- 分支尚未合并、未推送；交由你编译测试后再审查合并。

原先未提交的界面状态文件、`.DS_Store`、设计预览与其他文档未纳入这些提交。
