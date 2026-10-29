# 中英双语（i18n）交接文档

目标：App 支持简体中文 + 英文，**跟随系统语言**（iOS 会自动在"设置 → 本 App → 语言"里提供切换，不做 App 内切换开关）。
中文仍是开发语言和默认语言。

请在新分支上做（如 `codex/i18n`），分阶段提交，做完交给用户编译测试，再由 Claude 审查合并。

---

## ⚠️ 最重要：内部逻辑用中文名当键，绝对不能改

App 和 Python 工具里大量逻辑把**物品 / 建筑 / 配方的中文名**当成标识用。国际化只能改**显示**，
数据和逻辑里的中文名一律保持不变。下面这些都不许动：

- `ItemCatalog.byName`、`RecipeViewModel.recipes`（按产物中文名分组）、`Recipe.inputs/outputs[].name`
- `FlowSimulator` 里的物品名判断：`vaporizerGases`（"惰气""水蒸气""酸气""息壤气"）、`transmuterActivators`、
  废水处理机能吃的"污水/壤晶废液/惰性壤晶废液"、`ProductionStats` 里各种 `[String: Double]` 的 key
- `RecipeViewModel.isMiningMachine`（看机器名里有没有"矿机""水泵""采种机""种植机"）、`isLikelySolid` 这类按名字猜的逻辑
- `Recipe.requiredEnv` / `gasEnvName`（"稳定环境"等）
- `MapType` 的 rawValue（"四号谷地""武陵"……）——**存档里存的就是这个字符串**，改了旧存档读不出来；显示用 `displayName`，可以让 `displayName` 返回本地化文字
- 所有 `@AppStorage` / `UserDefaults` 的 key、存档 JSON 字段、预设 JSON（`other/preset_*.json`）
- `Tools/presetlib.py`、`Tools/gen_presets.py` 里的中文名
- `FeedbackView` 里 CloudKit 记录的字段值（category 可以继续存中文）

判断原则：**这个字符串会被拿去比较、查字典、存盘吗？会 → 不动；只是给人看 → 本地化。**

---

## 阶段 1：游戏数据的英文名（物品、建筑、分类、模式）

游戏解包数据里有官方英文：`EndfieldData/TableCfg/I18nTextTable_EN.json`（跟 `I18nTextTable_CN.json` 同结构，按文本 id 查）。
`Tools/gen_datapack.py` 现在用 CN 表把 `ItemTable` / `FactoryBuildingTable` 等的 `name.id` 翻成中文名。

1. 在 `gen_datapack.py` 里同样加载 EN 表，**另外生成一个新文件** `EndfiledPlanner/other/names_en.json`：
   ```json
   {
     "items":      { "<itemId>": "English name", ... },
     "devices":    { "<device id>": "English name", ... },
     "categories": { "<category id>": "English name", ... },
     "modes":      { "<mode id>": "English name", ... }
   }
   ```
   - 不要往现有 `items.json` / `devices.json` / `recipes.json` 里加字段——旧版本 App 会通过"在线更新数据"读到新文件，
     改结构有风险；单独一个文件最安全
   - 英文缺失的条目就不写（App 里回退显示中文）
   - 手写的分类"核心"（`hub`）给个英文 "Core"
2. 输出要**确定、跨平台逐字节一致**：key 排序（`sort_keys=True` 或按 id 字符串排序）、`ensure_ascii=False`、LF 换行，
   跟现有 `write_json` 写法一致。这个脚本在用户的 Windows 机器上定时自动跑（`Tools/update_data.py`），Mac 和 Windows 输出必须一样
3. `Tools/gen_manifest.py` 生成的清单要包含 `names_en.json`（看现有清单怎么列文件的，照着加），这样在线更新能下发它
4. App 里加载：仿照 `ItemCatalog` 用 `DataPackStore.decode(..., resource: "names_en")` 读（下载的数据优先、再读安装包），
   读不到就当没有英文
5. 加一个统一的"显示名"入口，例如：
   ```swift
   enum DisplayName {
       static func item(_ chineseName: String) -> String      // 通过 ItemCatalog.byName 找 itemId → 英文；非英文环境或没有英文就返回原中文
       static func device(id: String, fallback: String) -> String
       static func category(id: String, fallback: String) -> String
   }
   ```
   当前语言是否英文用 `Locale.preferredLanguages.first?.hasPrefix("en")` 或 `Bundle.main.preferredLocalizations.first == "en"` 判断（二选一，全 App 统一）
6. 把**所有显示物品 / 建筑 / 分类名的地方**改成走 `DisplayName`。显示数据名用 `Text(verbatim:)`，避免被当成本地化 key：
   - 配方查询（搜索建议、物品列表、配方树节点、详情）
   - 产量计算（步骤、原料、副产物、选产物的搜索列表——搜索同时匹配中英文）
   - 基建：建筑卡片名、建造面板、详情面板、管线详情、产能统计、高亮提示条、地图冲突提示里的建筑名
   - `SearchablePickerSheet` 的条目标题
   - `ItemIcon` 的 `name` 参数**仍然传中文名**（它用中文名查图标），只改旁边显示的文字
7. 机器名：`Recipe.machine` 是中文且可能带"（稳定环境）"后缀。英文显示时用 `DisplayName.device(id: recipe.machineId, ...)`，
   环境后缀单独本地化拼上

---

## 阶段 2：界面文字（String Catalog）

现状：47 个 Swift 文件里约 700 条不重复的中文字符串。

1. 新建 `EndfiledPlanner/other/Localizable.xcstrings`（String Catalog），开发语言 zh-Hans，加 en
   - 工程用的是文件夹同步（file system synchronized groups），新文件放进去会自动加入 target
   - 工程设置里 Localizations 加上 English
2. **字面量**（`Text("配方分析")`、`Button("取消")`、`Label("…", systemImage:)`、`.navigationTitle("…")`）编译时会自动收进目录，填英文即可
3. **非字面量**要改写，不然不会被收集、也不会翻译：
   - 存在变量 / 计算属性 / 数组里的界面文字（如 `HomeView` 的入口标题、`FactoryGuideView.sections`、`FeedbackView.Category` 的显示名、
     `MachineStatus.label`、`BuildingCategory` 的显示名、工具栏 `tool("选择", …)` 这类函数参数）→ 用 `String(localized: "…")`，
     或者参数类型改成 `LocalizedStringKey` / `LocalizedStringResource`
   - 带插值的：`"今天还能发 \(n) 条"` → `String(localized: "今天还能发 \(n) 条")`，目录里会出现带 `%lld` 的条目；
     英文里有单复数的用目录自带的 Vary by Plural
   - `String(format:)` 拼的提示改成插值 + `String(localized:)`
   - 枚举 rawValue 当显示文字的（如 `FeedbackView.Category`、`MapType`）：rawValue 不动，加一个本地化的 `displayName`
4. **不翻译**：社区蓝图的标题、说明、作者（作者写的内容，保持原样）；蓝图分区"四号谷地 / 武陵"可以翻译显示
5. 英文翻译要求：
   - 游戏术语以阶段 1 的官方英文为准（物品、建筑名），界面里提到建筑时保持一致
   - 简洁，按钮尽量 1~2 个词；英文通常比中文长，检查窄屏（iPhone SE 宽度）不截断、不换行错乱
   - 不确定的游戏术语列出来，交给用户确认

---

## 阶段 3：长文本

- `FactoryGuideView`（使用指南）、`OptimizerDisclaimer`（免责声明）、`BlueprintDisclaimerView`、产量计算的说明、
  反馈页的说明文字等，整段翻译
- 设置页的分组标题现在是英文（"ABOUT""GAME DATA"），中文环境下保持原样也行，统一即可

---

## 不在范围内

- App 内语言切换开关（跟随系统即可）
- 蓝图数据（`blueprints.json`）的翻译
- 预设、存档格式的任何改动
- 改动模拟逻辑

---

## 验收清单（交给用户测试前自查）

- [ ] 系统语言中文：界面、数据名跟改动前完全一样
- [ ] 系统语言英文：首页、配方查询、产量计算、社区蓝图（除作者内容）、基建（工具栏、面板、统计、指南）、设置、反馈都是英文
- [ ] 英文环境下：加载两个预设，产能统计数字跟中文环境一致（证明没改坏按名字判断的逻辑）
- [ ] 英文环境下：产量计算"灼铜装备原件 6/分钟"的机器台数跟中文环境一致
- [ ] 旧存档（中文环境保存的）在英文环境能正常打开，地图名显示英文
- [ ] `python3 Tools/gen_datapack.py` 重新生成后，除新增的 `names_en.json` 和清单外，现有 JSON 没有变化（`git diff` 为空）
- [ ] `python3 Tools/gen_presets.py` 跑通，预设无变化
- [ ] 窄屏（iPhone SE / 分屏 iPad）英文不截断
- [ ] 列出拿不准的术语译名
