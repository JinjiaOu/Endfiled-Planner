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

### M3 管线详情 + 线跟随建筑 + 操作优化（已完成）
1. **管线详情**：点传送带/管道弹面板（速度、长度、当前货物和实际流量、状态；删除整条/这一格），布局同 M2（iPad 右侧、iPhone 底部）；`FlowSimulator.Link` 记录来源 Belt ID，`Result` 暴露按带的流量；选中后整条线高亮。
2. **管道上限已确认为 2/秒（120/分钟）**（用户 2026-10-02 确认），`FlowSimulator.pipeCapacity` 保持 2.0，去掉代码里"尚未确认"的注释。
3. **移动建筑时线跟着走**：拖拽重定位、详情面板"移动"、旋转后，原来接在这台建筑端口上的传送带/管道要跟着改，不能还钉在旧位置。思路：移动前记下每个端口接着的线（线头/线尾落在端口外部格上），移动后把这些线靠近建筑的那一端重新布到新端口位置（另一端不动，中间用现有 L 形路由重算；重算失败就断开该线并提示）。
4. **操作优化**（用户 2026-10-02 提出三点，下面是方案，标"待确认"的要先问用户）：
   - ~~画线跟手改路线~~：做过后用户试用（2026-10-06）觉得转弯时歪歪扭扭、不沿格子，**已撤回，保持原来的 L 形画线**。以后要改画线手感，先跟用户确认方案。
   - **删除更方便**：
     - 加**撤销/重做**（布局快照栈，所有改动都能撤，不只是删除），有了撤销就去掉删除的确认弹窗，只保留"删除整条线"的确认（用户 2026-10-02 定）。
     - 删除工具支持**按住划过去连删**：划过的线格逐格删掉，划过建筑直接收纳（协议核心照旧不能删）。
     - 建筑/管线详情面板里都有删除按钮（建筑已有"收纳"，管线详情在本里程碑第 1 项做）。
   - **选中更方便**：
     - 传送带/管道也能点选（配合第 1 项管线详情），点中整条高亮。
     - 不用先切到"选择"工具：放置模式下点已有建筑/线直接选中它，点空地才放建筑；画线模式下单击（不拖）也算选中。
     - 点空白处取消选中；选中后网格上加明显的选中框。
     - 缩小看全图时建筑和线的可点范围按最小 44pt 放大，避免点不中。

### M4 地图限制 + 框选 + 我的布局（蓝图）（未开始，用户 2026-10-06 定方案）
名字定为"我的布局"（App 里已有的"蓝图"页是游戏蓝图码收录，避免混淆）；工具栏拿掉"旋转"（详情面板里已有），换成"框选"，"我的布局"入口也放工具栏。分四步，每步交用户测一次：

**0. 地图限制（平时编辑也生效，蓝图冲突检查复用同一套规则）**
- 地图规则集中成一张"地图规则表"（每张地图一条：能不能用水用气、仓库取线方式、专属建筑名单、可用配方模式、画布大小），代码里不再到处写 `switch mapType`；以后加新地图基本只要加一条记录，M5 的数据包也能顺带更新这张表（用户 2026-10-07 同意）。
- 只能在武陵用的建筑：水泵、二型耐酸水泵、气体收集泵、水驱矿机、反应池、扩容反应池、液气转化机、固气转化机、提纯机、气体反应炉、天有洪炉、废水处理机、气体散布机、储液罐、储气罐、暗管入口/出口（含多口）、拆解机、息壤供电桩，以及原有的仓库存取线源桩/基段。四号谷地没有水泵（用户确认），用水用气的设备都只在武陵。
- 两图都能放、但四号谷地只能用基础模式配方：精炼炉、灌装机、塑形机、种植机（配方按 devices.json 的 modes / recipes 的 formulaGroupId 对应到模式，液体/气体/气液模式配方在四号谷地标灰"仅武陵"）。
- 拆解机仅限武陵（用户 2026-10-06 更正：先说两图都能用，后确认只能在武陵）。
- 四号谷地建造栏不显示武陵专属建筑。
- 冲突状态要随时重算，不只在放置时判断一次（见第 3 步取货口的情况）。

**1. 框选 + 整组操作**
- "框选"工具下拖出选框，建筑整个落在框内才算选中；协议核心不参与。点单个建筑可加入/移出选中。
- 多选面板：移动、删除、存为布局、取消。
- 按住任一选中建筑拖动整组，跟手预览（绿=能放，红=撞到）。组内两头都接组内建筑的线跟着平移；一头接组外的线用 M3 的改接逻辑，走不通就断开提示。整组操作算一步撤销。

**2. 保存 + "我的布局"列表**
- 存：建筑相对位置、朝向、配方（含反应池多选）、取货材料、准入口限速、输出口分配、开关状态；整条都在框内的线（相对位置）；名字、创建时间、建筑数、来源地图、缩略图。
- 先存本机；以后需要再加导出/导入文件。

**3. 放置**
- 列表里点一个 → 整组虚影出现在画面中央，跟手拖动、可整体旋转 90°，点"确认"才写入（一步撤销），可取消。
- 压到已有建筑：必须挪开才能确认。
- 跨地图（用户定：可以放，但放之前提醒，放下后冲突建筑标红）：
  - 放之前弹窗列出冲突建筑和数量，选"仍然放置"/"取消"。
  - 冲突建筑照样放进布局，红框 + "地图不支持"，不参与模拟（像关闭的建筑）。
  - 冲突来源：武陵专属建筑放到四号谷地；用了液体/气体配方的精炼炉/灌装机/塑形机/种植机放到四号谷地；仓库取货口/存货口（两个方向都会冲突）。
  - 取货口/存货口不是死冲突：放到武陵后，用户再摆好源桩和基段让它们贴上，红色自动消失。
- 配方 ID 在新版数据里找不到的机器显示"未设置"。

### M5 App 内一键更新数据（未开始，排在 M4 后）
- 打包脚本：生成脚本跑完后，把 JSON 数据和新增/变化的图标打成数据包 + 小清单文件（版本号、格式版本、校验和），传到固定地址（国内优先 Gitee Release）。
- App：设置里"检查数据更新" → 比版本 → 下载、校验 → 存到 App 自己的文件夹，下次启动（或立即）改用新数据；可一键恢复安装包自带的数据。
- 图标：内置图标集只读，下载的图片存成普通文件，显示时先找下载的、再找内置的。
- 兼容：数据包格式版本比 App 认识的新时拒绝更新、提示升级 App；配方 ID 消失时数据包附带迁移表（同 M1）。
- 只下载数据不下载代码，符合上架规则；新地图如果有全新的取线机制仍要发新版 App。

### 小缺口（用户 2026-10-07 定，未开始）
1. **分流器堵一路**（已完成）：某一路出口堵住（下游吃不下）后，原本分给它的流量全部改分给剩下没堵的出口，平均分；现在是严格三等分、整台跟着降速，统计偏悲观。要同步改 `Tools/presetlib.py` 的模拟并重新生成预设。
2. **准入口按物品过滤**（已完成）：物品准入口/管道准入口除了限速，还能指定"只让某种物品通过"（不设置 = 全部通过），过滤掉的物品视为堵住。
3. **地下暗管不做连通**（已完成）：暗管入口和出口之间的连通/限流不模拟了。暗管出口（单口、多口）像仓库取货口一样设置"出什么"，**只能选液体和气体**（用户 2026-10-07 确认），多口暗管也只出一种材料，按管道上限往外送；暗管入口当终点处理，送进去的液体全收、不堵上游。（入口全收用户 2026-10-07 已确认。）
- 原 TODO 待补清单里的"地下暗管限流（单位待查）"随第 3 条作废。

### M1.5 电力：供电桩覆盖 + 热能池发电（已完成）
规则（用户 2026-10-01 定）：
- 所有建筑必须在供电桩范围内才能运行。供电桩 `power_diffuser_1` 和息壤供电桩 `power_diffuser_2` 没区别；**不做**中继器 `power_pole_2/3`（从建造栏隐藏）。
- 热能池 `power_station_1` 发电，发电量取决于烧什么燃料，不是固定的 150。

解包数据（`TableCfg`）：
- `FactoryPowerPoleTable.json`：两种供电桩都是 `rangeExtend {x:5, z:5}`。覆盖范围是供电桩 2×2 本体向四周各扩 5 格（12×12），用户 2026-10-06 在游戏里核对无误。
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

### M8 收尾（已完成，2026-10-06）
抽查 Codex 各分支（`git diff --stat` + 验收输出），合并，更新 `EndfiledPlanner-TODO.md`，提交。

---

## 冲突规避
- 阶段一 Codex 改的 Swift 文件：`SearchablePickerSheet`、`FactoryStatsView`、`FactoryLayoutView`、`FactoryGridView`、`FlowSimulator.MachineStatus.label`，新增 `ItemIcon.swift`。不碰 `Recipe*`、`PlacedBuilding`、`BuildingParser`、`FlowSimulator` 其它部分。
- 阶段一期间 Claude 不改任何代码，只做设计；阶段二开始前先合并 `codex/batch1`。
- 阶段二里 M1 之后 `ItemIcon(name:)` 仍可用（名字查 itemId），不用回头改 Codex 铺的调用点。

## 暂不做
远程数据包（TestFlight 阶段靠重新发构建，注意构建 90 天过期）、素材版权处理、逆转流向、"自动处理复数配方阻塞"开关、视觉换肤。
