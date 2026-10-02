# 后续计划（数据管线 → 图标 → UI 改版）

分工原则：量大且规则明确的交给 Codex；涉及架构、模型改动、手势、模拟器的交给 Claude。
省 token 约定：Codex 任务书自包含，不让它读 `EndfiledPlanner-TODO.md`；验收用脚本/命令，不人工通读 diff；
Claude 只看 `git diff --stat` 和验收输出，必要时抽查具体 hunk；编译和运行由对方/用户做，不重复。

通用规则（写给 Codex）：
- 每个任务单独分支 `codex/<任务编号>`，只改任务书列出的文件，做完单独提交，提交信息以任务编号开头。
- 编译命令：`xcodebuild -project EndfiledPlanner.xcodeproj -scheme EndfiledPlanner -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD"`
- 不动 `.xcuserstate`；不提交 `item_downloader.py`（里面有 DID）；Swift 文件和 Claude 同时改时先等通知（见"冲突规避"）。
- 全部 UI 文案中文。新 Swift 文件头注释 `// Created by Jinjia Ou on [日期].`

---

## 步骤总览

只切换一次：Codex 在分支 `codex/batch1` 上按顺序一次做完 C1→C2→C3→C4→C5，你测过编译后合并，再交给 Claude 做 M1→M2→M3。

| 阶段 | 谁 | 内容 |
|---|---|---|
| 一 | Codex（一次跑完） | C1 数据生成脚本 → C2 素材搬家+图标脚本 → C3 `ItemIcon` 视图并铺开 → C4 网格状态角标 → C5 文案统一 |
| 二 | Claude | M1 App 改读 JSON + 存档改记配方 ID + 旧存档迁移 → M1.5 电力（供电桩覆盖 + 热能池燃料）→ M2 建筑详情面板 → M3 管线详情 → 收尾 |

给 Codex 的一句话：
"读 PLAN.md 的『通用规则』和 C1–C5，在分支 codex/batch1 上按顺序全部做完，每个任务单独提交，最后汇报每个任务的验收输出。不要读其它文档。"

---|---|---|---|
| 1 | Codex | C1 数据生成脚本（TableCfg → JSON 数据包） | 无 |
| 2 | Claude | M1 App 改读 JSON + 存档改记配方 ID + 旧存档迁移 | C1 |
| 3 | Codex | C2 素材搬家 + 图标生成脚本 | C1 |
| 4 | Claude | M2 `ItemIcon` 视图（小）+ 详情面板 | C2 |
| 5 | Codex | C3 图标铺到各列表/标签 | M2 的 `ItemIcon` |
| 6 | Claude | M3 管线详情（含模拟器暴露带流量） | M2 |
| 7 | Codex | C4 网格状态角标 + C5 文案统一 | M2、M3 |
| 8 | Claude | 收尾：抽查、合并、TODO 更新 | 全部 |


---

## Codex 任务

### C1 数据生成脚本
目标：`Tools/gen_datapack.py`，从解包仓库生成数据包，替代手改的 `recipes.txt` / `devices_generated.json`。
输入：`/Users/owen/Desktop/Project/EndfieldData/TableCfg`（参数 `--tablecfg` 可指定目录）、`I18nTextTable_CN.json`。
输出到 `EndfiledPlanner/other/`：`recipes.json`、`devices.json`、`items.json`、`datapack_meta.json`（含解包仓库 commit、生成时间、schemaVersion=1）。
- `recipes.json`：沿用现有 `other/recipes_generated.json` 的结构（`id/type/machineId/machineName/seconds/gasEnv/gasEnvName/ingredients/outcomes`，物品带 `itemId/name/count`），并新增 `type:"gasMining"`，来源 `FactoryGasMinerTable.json`（气体收集泵，产出息壤气、惰气，3s，id 形如 `gas_pump_1:0`）。
- `devices.json`：沿用现有 `other/devices_generated.json` 的结构，新增字段 `powerGenerate`（来源：`FactoryPowerStationTable.powerProvide`、`FactoryHubTable.powerGenerate`，其余为 0）；新增 `sp_hub_1`（协议核心，categoryName "核心"，端口取自 `FactoryBuildingTable`）；**不要**输出 `sp_sub_hub_1`。
- `items.json`：所有出现在配方里的物品 `[{itemId,name,phase}]`，`phase` 规则：itemId 以 `item_liquid_` 开头为 `liquid`，`item_gas_` 开头为 `gas`，其余 `solid`（"已盛装"容器也是 `solid`）。
- 覆盖规则放在脚本顶部一个字典里：水泵 `pump_1` 只保留清水（`pump_1:0`），其余 `pump_1:*` 剔除。
验收（脚本末尾自动检查并打印）：
1. 与现有 `other/recipes_generated.json` 按 `id` 对比：`removed=0`、`changed=0`，`added` 包含 12 条新增实验类配方 + gasMining 配方。
2. `devices.json` 里 `sp_hub_1` 存在、`sp_sub_hub_1` 不存在，`power_station_1.powerGenerate=150`、`sp_hub_1.powerGenerate=200`。
3. 重复运行输出完全一致（字段顺序固定、`indent=2`、不写时间戳以外的随机内容）。
不要改 Swift。

### C2 素材搬家 + 图标生成脚本
- 把 `EndfiledPlanner/物品/` 整个移动到项目根目录 `素材原图/物品/`（不在 Xcode 同步目录里）。
- `Tools/gen_icons.py`：读 `items.json` + `素材原图/物品/*.png`（文件名 `名称_wiki编号.png`）+ `Tools/icon_alias.json`（初始内容 `{"实验息壤铜骨骼":"实验息壤铜骨架"}`，键为游戏名，值为 wiki 名）。
- 匹配规则，按顺序：① 游戏名精确等于 wiki 名；② 过一遍别名表；③ 名称含"（已盛装"：取括号前的名字（如 `蓝铁瓶`）再按①②匹配，记为 `fallback`。
- 输出：`EndfiledPlanner/other/ItemIcons.xcassets/<itemId>.imageset/`（`sips -Z 192` 缩放后的 png + `Contents.json`，单倍图即可）；`Tools/icon_report.json`：`{matched:[], fallback:{itemId:baseItemId}, unmatched:[], wikiUnused:[]}`。
- 只处理 `items.json` 里的物品，其余 wiki 图（食物等）也要导入：对 wiki 里存在、游戏 `ItemTable.json` 里按中文名唯一对应（排除 `sysbp_` 前缀）的物品，同样生成图集，键为游戏 itemId。
验收：配方物品里 `unmatched` 为 0（容器类走 `fallback`）；`ItemIcons.xcassets` 总大小 < 6MB；`git status` 里 `物品/` 已不在 `EndfiledPlanner/` 下。

### C3 `ItemIcon` 视图并铺开
- 新建 `ItemIcon.swift`：`ItemIcon(name: String, size: CGFloat)`。按物品中文名在 `items.json`（运行时从 bundle 读一次并缓存，名字在该文件里唯一）查 itemId，再取资源 `Image(itemId)`；没有对应图时用 `Tools/icon_report.json` 里的 `fallback`（同样需要打进 bundle，可复制一份为 `icon_fallbacks.json` 放 `other/`）；都没有就显示一个按 phase 区分的 SF Symbol 占位（固体 `cube`、液体 `drop`、气体 `cloud`）。
- 铺到：`SearchablePickerSheet` 行首和筛选标签（需要给 `SearchablePickerItem` 加可选 `iconName`）、取货口材料选择行、`FactoryStatsView` 的产线和终点消耗行、`FactoryLayoutView` 里原料/产物文字旁。只加图标，不改逻辑。
- 用名字查，不要动 `Recipe`/存档相关代码（Claude 之后会改）。

### C4 网格状态角标
`FactoryGridView.buildingCard` 右上角加状态点：运行绿、阻塞红、缺料橙、未激活灰，状态取自 `vm.stats.machineStates` 里同 id 的 `status`；`placed.isActive == false` 的建筑整体降低不透明度并显示灰点。没有对应状态的建筑（物流节点等）不显示。

### C5 文案统一
纯字符串替换，不改逻辑：删除建筑→收纳、功率→耗电功率值、选择配方→配方一览、输出口→选择输出产物（按钮"更换"）、出口堵塞→阻塞、运行中→生产中。范围：`FactoryLayoutView`、`FactoryStatsView`、`FlowSimulator.MachineStatus.label`。完成后列出所有被改的字符串位置。

---

## Claude 任务

### M1 App 改读 JSON + 存档改配方 ID（C1 完成后）
- `Recipe` 增加 `id` 和各物品的 `itemId`；`RecipeViewModel` 改读 `recipes.json`，环境要求直接用 `gasEnvName`，不再解析"（稳定环境）"机器名后缀；固体/液体/气体判断改用 `items.json` 的 `phase`，删掉按名字猜的 `isLikelySolid`。
- `BuildingParser` 改读 `devices.json`（含 `powerGenerate`、协议核心）。
- `PlacedBuilding`：`selectedRecipeIndex/Indices` 改为 `selectedRecipeID/IDs`；旧存档读取时用"旧排序下标→配方 ID"的快照表一次性迁移；`FactoryLayout` 加 `dataVersion`。取货口材料也改记 itemId。
- 删除已经被取代的 `recipes.txt`、`recipes_generated.*`、`devices_generated.*`。
- 做完编译，请用户测一遍存档加载、配方选择、两条测试产线。

### M2 建筑详情面板（已完成）
- 图标直接用 Codex 在 C3 做好的 `ItemIcon`。
- 建筑详情面板：iPad 右侧面板、iPhone 底部 sheet（展开时网格仍可操作，不能破坏拖拽重定位）；通用头部（名称、耗电功率值、开/关、移动、旋转、收纳、状态条）+ 按类型的主体（普通配方机、反应池/扩容的物料槽与 3 个输出产物槽、转化机/散布机激活仪表、准入口限速、取货口材料、协议核心）。
- 模拟器暴露：各原料到货量、激活口到货量、`isActive` 关机处理。
- 移动按钮：先做"点按目标位置"，保留现有拖拽。

### M3 管线详情 + 线跟随建筑 + 操作优化
1. **管线详情**：点传送带/管道弹面板（速度、长度、当前货物和实际流量、状态；删除整条/这一格），布局同 M2（iPad 右侧、iPhone 底部）；`FlowSimulator.Link` 记录来源 Belt ID，`Result` 暴露按带的流量；选中后整条线高亮。
2. **管道上限已确认为 2/秒（120/分钟）**（用户 2026-10-02 确认），`FlowSimulator.pipeCapacity` 保持 2.0，去掉代码里"尚未确认"的注释。
3. **移动建筑时线跟着走**：拖拽重定位、详情面板"移动"、旋转后，原来接在这台建筑端口上的传送带/管道要跟着改，不能还钉在旧位置。思路：移动前记下每个端口接着的线（线头/线尾落在端口外部格上），移动后把这些线靠近建筑的那一端重新布到新端口位置（另一端不动，中间用现有 L 形路由重算；重算失败就断开该线并提示）。
4. **操作优化**（用户 2026-10-02 提出三点，下面是方案，标"待确认"的要先问用户）：
   - **画线跟手改路线**：现在只能从起点拉一个 L 形（最多一个拐角）。改成线跟着手指走过的格子铺：手指拐几次线就拐几次，往回退会把走过的那段收回；手指划得太快跳格时，两点之间用直线/L 形补齐；终点照旧自动吸附端口。
   - **删除更方便**：
     - 加**撤销/重做**（布局快照栈，所有改动都能撤，不只是删除），有了撤销就去掉删除的确认弹窗，只保留"删除整条线"的确认（用户 2026-10-02 定）。
     - 删除工具支持**按住划过去连删**：划过的线格逐格删掉，划过建筑直接收纳（协议核心照旧不能删）。
     - 建筑/管线详情面板里都有删除按钮（建筑已有"收纳"，管线详情在本里程碑第 1 项做）。
   - **选中更方便**：
     - 传送带/管道也能点选（配合第 1 项管线详情），点中整条高亮。
     - 不用先切到"选择"工具：放置模式下点已有建筑/线直接选中它，点空地才放建筑；画线模式下单击（不拖）也算选中。
     - 点空白处取消选中；选中后网格上加明显的选中框。
     - 缩小看全图时建筑和线的可点范围按最小 44pt 放大，避免点不中。

### M1.5 电力：供电桩覆盖 + 热能池发电（已完成）
规则（用户 2026-10-01 定）：
- 所有建筑必须在供电桩范围内才能运行。供电桩 `power_diffuser_1` 和息壤供电桩 `power_diffuser_2` 没区别；**不做**中继器 `power_pole_2/3`（从建造栏隐藏）。
- 热能池 `power_station_1` 发电，发电量取决于烧什么燃料，不是固定的 150。

解包数据（`TableCfg`）：
- `FactoryPowerPoleTable.json`：两种供电桩都是 `rangeExtend {x:5, z:5}`。**假设**：覆盖范围是供电桩 2×2 本体向四周各扩 5 格（12×12），实现后请在游戏里核对一次。
- `FactoryFuelItemTable.json`（`powerProvide` 是烧该燃料时的发电量，`progressRound` 是每个燃料烧多少秒）：

  | 燃料 | 发电 | 每个烧 | 每台耗燃料 |
  |---|---|---|---|
  | 源矿 | 50 MW | 8 s | 7.5/min |
  | 低容谷地电池 | 220 MW | 40 s | 1.5/min |
  | 中容谷地电池 | 420 MW | 40 s | 1.5/min |
  | 高容谷地电池 | 1100 MW | 40 s | 1.5/min |
  | 低容武陵电池 | 1600 MW | 40 s | 1.5/min |
  | 中容武陵电池 | 3200 MW | 40 s | 1.5/min |
- 协议核心固定发电 200 MW，计入总发电，但**没有供电范围**（用户已确认），周围建筑仍要靠供电桩。

要做的：
- `gen_datapack.py` 导出燃料表（新文件或并入 `devices.json`）和供电桩范围；App 读取。
- 模拟器：热能池作为终点消耗燃料，按实际到货率算发电量（到货不足按比例）；不在任何供电桩范围内的建筑状态为"未通电"（灰），不运行。
- 总发电 < 总耗电时的处理方式待定：先只在统计面板标红提示"电力不足"，不做按比例降速（等游戏实测再定）。
- 网格上选中供电桩时画出覆盖范围；统计面板显示 耗电 / 发电（按燃料分项）/ 未通电建筑数。
- 已确认：只有耗电 > 0 的建筑需要在供电桩范围内；分流器、汇流器、物流桥、准入口这类物流建筑不需要（跟解包表 needPower 一致）。
- 两个内置预设补上供电桩 + 热能池（燃料从仓库取电池），`presetlib.py` 同步加覆盖检查，保证预设在新规则下仍全部运行。

### M8 收尾
抽查 Codex 各分支（`git diff --stat` + 验收输出），合并，更新 `EndfiledPlanner-TODO.md`，提交。

---

## 冲突规避
- 阶段一 Codex 改的 Swift 文件：`SearchablePickerSheet`、`FactoryStatsView`、`FactoryLayoutView`、`FactoryGridView`、`FlowSimulator.MachineStatus.label`，新增 `ItemIcon.swift`。不碰 `Recipe*`、`PlacedBuilding`、`BuildingParser`、`FlowSimulator` 其它部分。
- 阶段一期间 Claude 不改任何代码，只做设计；阶段二开始前先合并 `codex/batch1`。
- 阶段二里 M1 之后 `ItemIcon(name:)` 仍可用（名字查 itemId），不用回头改 Codex 铺的调用点。

## 暂不做
远程数据包（TestFlight 阶段靠重新发构建，注意构建 90 天过期）、素材版权处理、逆转流向、"自动处理复数配方阻塞"开关、视觉换肤。
