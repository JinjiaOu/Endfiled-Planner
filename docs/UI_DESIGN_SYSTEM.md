# Phase 2 · 设计系统实施与使用说明

日期：2026-10-19。方向：工业终端视觉、原生 iOS 控件、清晰数据排版。

**按用户最新要求，本阶段不由代理执行构建、运行、Preview、截图或测试，全部交给用户验证。以下为代码实现说明，不是验证通过记录。** 未提交 Git Commit。

## 1. 已实施范围

新增 `EndfiledPlanner/DesignSystem/`，不依赖第三方库，不绑定任何 ViewModel / Service / 持久化单例。文件位于项目已有的文件系统同步目录，不需要更改 project.pbxproj。

| 文件 | 内容 |
|---|---|
| `AppTheme.swift` | 语义颜色、动态深浅色、增强对比度边界 / 辅助文字、语义字体、间距、圆角、尺寸、遵循 Reduce Motion 的动画、页面样式 |
| `Components/AppSurface.swift` | 普通 / 浮层表面、页面标题、分组标题 |
| `Components/AppActions.swift` | 主操作 / 次操作 / 危险操作按钮样式、具名图标按钮、持续显示名称的工具按钮 |
| `Components/AppSelection.swift` | 搜索输入框、筛选标签、单选 / 多选行、限制原因与无障碍状态 |
| `Components/AppStatusViews.swift` | 状态语义、状态徽标、行内提示、空态 / 错误排版、加载与进度、短反馈 |
| `Components/AppMetricViews.swift` | 指标、可随字号重排的指标栅格、宽度不足时纵排的名称 / 数值行 |
| `Components/AppInspectorContainer.swift` | 非模态底部 / 侧面属性容器，标题、折叠、关闭、滚动内容、常驻动作 |
| `DesignSystemGallery.swift` | 独立组件目录，含深色、浅色、最大无障碍字号三个 Xcode Preview 声明 |

首次接入两个已有组件：

1. `ProductionOptimizer/View/SearchablePickerSheet.swift`：用通用筛选标签、选择行、空结果状态和主题替换本地样式；改用语义字体，选中态同时有勾选及 VoiceOver 状态，限制原因放在正文下方以减少长文本挤压。搜索和原料过滤算法、单选关闭、多选回调、清空、禁用但已选项可取消的规则保留。
2. `DataPack/DataUpdateBanner.swift`：使用表面、状态、进度和主按钮；大字模式将下载按钮放到说明下方。继续使用原 updater、原下载调用、原三种显示状态及“重启后生效”语义。

当前没有改造 Home、FactoryLayout、FactoryGrid、建筑 / 管线面板、统计主页面，也没有更改全局导航。Phase 3 的代表页改造尚未开始。

## 2. Token 使用约定

### 颜色

- `AppColors.background` / `canvas`：页面和二维工作区。
- `surface` / `elevatedSurface`：内容区域与浮层。
- `primaryText` / `secondaryText` / `tertiaryText`：文字层级，不使用白色透明度充当正文颜色。
- `border`：轻分隔；`controlBorder`：输入、选项等需要识别的边界。
- `accent`：前景强调色，浅色环境改用较深色；`accentFill` + `onAccent`：工业黄主按钮和深色按钮文字。
- `success` / `warning` / `error` / `info`：状态颜色；必须配合文字或符号。
- `disabledSurface` / `disabledText`：禁用控件。

颜色由 UIKit 动态 provider 跟随系统深浅色，增强对比度时进一步加强辅助文字和边界。**没有强制整个 App 深色，没有读写旧 `darkMode` 设置，也没有进行颜色对比度测量。** 旧页面仍使用原外观，后续逐页接入，当前不要期待整个 App 已统一主题。

分类、端口和固液气线路的显示映射留到 Phase 3 结合原画布定义接入，当前没有替换现有业务分类色，也没有让通用状态色改变线路含义。

### 字体、尺寸、动画

- `AppTypography` 使用 `.title2`、`.headline`、`.body` 等系统语义字体；指标用等宽数字，代码用等宽字体。
- `AppSpacing`：4 / 8 / 12 / 16 / 20 / 24 / 32。
- `AppRadius`：4 / 6 / 2（2026-10-20 视觉稿落地后）；`AppSize.touchTarget` 为 44pt，行最小高度 52pt，允许内容增高。
- 大字指标栅格采用单列；名称 / 数值行会根据可用宽度回退为纵向排列。
- `AppMotion.feedback` / `panel` 由调用方传入 Reduce Motion 值；开启 Reduce Motion 时不播放自定义动画。
- 不在组件内部自动创建业务计时器、保存用户数据、下载内容或连续播报数值。

## 3. 常见用法

### 页面与主操作

```swift
VStack(alignment: .leading, spacing: AppSpacing.md) {
    AppPageHeader(title: "基建规划", subtitle: "四号谷地")
    Button("保存画布") { vm.saveLayout() }
        .buttonStyle(AppActionStyle())
}
.padding(AppSpacing.md)
.appPageStyle()
```

`appPageStyle()` 不创建导航容器、不强制外观、不改变 VM 生命周期。危险操作需保留已有的 role 和确认逻辑；按钮样式只管视觉：

```swift
Button("删除布局", role: .destructive) { showDeleteConfirmation = true }
    .buttonStyle(AppActionStyle(emphasis: .destructive))
```

### 表面和指标

```swift
AppSurface {
    AppMetricGrid {
        AppMetricCell(title: "建筑", value: "\(stats.buildingCount)", unit: "座")
        // value 和 unit 均由原业务代码提供，组件不改变统计口径。
    }
}
```

不要把每个数据行都包成厚卡片。已有组内的名称 / 数值明细可直接使用 `AppKeyValueRow`。

### 选择行与受限项目

```swift
AppSelectionRow(
    title: item.title,
    subtitle: item.subtitle,
    isSelected: selected,
    multiSelect: true,
    restriction: item.disabledTag,
    isSelectable: item.disabledTag == nil || selected,
    hint: item.disabledTag != nil && selected ? "可取消选择" : "",
    action: { onToggle(item.id) }
) {
    ItemIcon(name: item.title, size: AppSize.itemIcon)
}
```

是否可选和业务限制必须由调用方传入。通用组件不访问地图规则，不自动过滤项目，也不修改选中集合。

### 非模态检查面板

```swift
AppInspectorContainer(
    title: "设施详情",
    isExpanded: $expanded,
    maxContentHeight: availableContentHeight,
    onClose: clearSelection
) {
    detailContent
} actions: {
    existingActions
}
```

侧面形式传 `placement: .side`；宽度和内容最大高度由父布局按实际可用区域决定。容器不创建 Sheet，动作区不随内容折叠隐藏。不要把它直接覆盖到整个画布上再让透明区域抢占触控；父页面仍需负责工具、面板与画布的空间分配。

### 反馈与系统弹窗

- 短反馈使用 `AppFeedbackToast`，出现 / 消失时机继续由原页面掌握。
- 错误和空态用 `AppContentState`，通过 actions 闭包传重试等动作。
- 提示使用 `AppInlineNotice`；状态文字从现有业务枚举映射，不按颜色推断状态。
- Alert、ConfirmationDialog、Menu、ShareSheet 保持原生，不在 Phase 2 新造弹窗系统。

## 4. 用户验证入口

Phase 3 补充：`AppInspectorContainer` 新增 `maxPanelHeight`。传入时采用整个面板滚动的受限高度布局，操作区位于标题后；未传入时仍使用原内容区滚动布局。`AppKeyValueRow` 新增可选 `valueColor` 显示参数。代表页接入说明见 [UI_PHASE3_HANDOFF.md](UI_PHASE3_HANDOFF.md)。

此节仅供用户操作，代理未执行：

1. 在 Xcode 打开 `DesignSystemGallery.swift`，选择“深色 · 组件目录”“浅色 · 组件目录”“大字 · 组件目录”的 Preview。
2. 在组件目录切换工具、筛选、选择、受限已选项、错误 / 空态、反馈及面板折叠，查看视觉与可用性。目录使用本地演示状态，不读取存档，不进入 App 正式导航。
3. 正式 App 中，进入基建的配方 / 物料选择器，查看搜索、单选、多选、清空、筛选、禁用原因，以及受限已选项仍可取消。
4. 如实际已有更新状态，可查看首页下载横幅；本阶段没有为演示注入或强造远端更新状态。
5. 按需检查系统浅色、深色、大字号、增强对比度、Reduce Motion 和 VoiceOver。

所有构建结果、实际显示和交互表现都等待用户反馈；本阶段没有生成“通过”记录，也没有新增自动化测试。


## 2026-10-20 · 已确认视觉稿落地

用户认可石墨灰 / 浅柠檬黄方案后，将共享深色 token 更新为：页面 `#111517`、画布 `#0C1012`、表面 `#191E20`、浮层 `#22282A`、细分隔 `#343C3E`、正文 `#E7EBE7`、辅助文字 `#A1ACA8`、强调 `#ECEE68`、成功 `#56B9A0`、警告 `#D68D55`。保留动态浅色、高对比度及原外观偏好。

检查器改用平直分区、标题旁短强调标记、细分隔和独立动作行。`summaryText` 用于折叠后仍保留关键数据；`disclosureTitle` 明确展开内容。普通尺寸下标题与动作保留在滚动区之外；低高度窗口、辅助字号下整个面板在限制高度内滚动并裁切。所有配置仍由原页面提供，容器不计算业务数据。

基建宽屏采用真实左右布局，不再用额外偏移避让浮层。详情见 [UI_TERMINAL_HANDOFF.md](UI_TERMINAL_HANDOFF.md)。本次未构建、运行、测试或生成实际 App 截图。


## 2026-10-20 · 工程图与等高线反馈

- `AppColors.canvas` 浅色改为中性工程纸 `#E7E7E5`；`FactoryCanvasPalette` 的纸面、设备、轮廓、文字与网格线均为动态颜色。物流带使用浅黄，管道使用与纸面对比的中性色，异常与利用率颜色保留独立含义。
- `AppTopographicBackground` 提供缓存等高线路径与低速漂移动画。工作台通过 `appPageStyle(topographicBackground: true)` 接入；配方与社区蓝图主页 / 详情、设置直接使用底纹组件。基建及其选择器未接入。默认 `appPageStyle()` 不附加底纹，避免影响共用选择器。
- 进入后台、页面不可见、低电量时暂停时间轴；减少动态效果时以固定时间绘制静态底纹。底纹不参与点击和辅助功能树，不修改显示设置的持久化键。
- `FactoryBuildingShell` 与 `FactoryTelemetryFrame` 是纯绘制组件，不持有 VM，不计算端口、产能或利用率。

本批交接见 [UI_BLUEPRINT_STYLE_HANDOFF.md](UI_BLUEPRINT_STYLE_HANDOFF.md)。未构建、运行、Preview 或测试。


## 2026-10-20 · 配方与社区蓝图收尾

两页及相关详情接入统一主题、原生导航标题、语义字体、搜索与动作组件和状态视图；延续用户确认后的细密等高线背景。配方页宽屏并排输入 / 结果，蓝图列表宽屏自适应列数，辅助字号回到纵向布局。

新增 `AppNoticeDialog` 为文档型提示提供统一标题、正文和动作，限制高度时整体滚动；组件不持有任何同意状态或持久化键。新增 `RecipeDiagramCard` 用于固定几何的树节点，`RecipeDependencyOutline` 为同一树提供可完整换行的语义字号清单。图形的固定字号随画布缩放，辅助字号默认使用清单，仍允许切回图形。

详情与用户验证入口见 [UI_FINAL_PAGES_HANDOFF.md](UI_FINAL_PAGES_HANDOFF.md)。未构建、运行、Preview 或测试。
