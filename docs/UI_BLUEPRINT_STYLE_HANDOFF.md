# 官方蓝图视觉参考 · 样式调整交接

日期：2026-10-20。参考为用户提供的官方蓝图截图（浅灰网格、黑灰设备轮廓 / 内框、端口槽、浅黄传送带）。不是对官方界面的完整复刻。

**按用户要求，未执行构建、运行、Preview、截图或测试；尚无本批实际运行验证结果。未提交 Git Commit。**

## 实施内容

1. 基建深浅色：移除画布固定深色底板。纸面、主次网格、设备外壳、文字、轮廓和未连接端口跟随系统外观。日间使用中性浅灰工程纸，夜间使用深石墨底色。
2. 利用率：切角边框、波形符号、明确的开启 / 关闭文字与状态短条。原切换、图例、真实建筑数量与统计入口继续使用原状态。画布中的部分负载百分比改为自适应浅 / 深色细框标牌；满载、空闲、瓶颈判断、数值公式和颜色状态没有改写。
3. 动态等高线：接入工作台、配方分析、配方详情、社区蓝图及详情、设置的页面背景，替换这些页面旧的固定底色与装饰网格。配套将这些页面的常见深色表面和白色文字改为语义 token，以适应浅色底纹。基建工作区、基建统计浮层、共用材料选择器不接入等高线。
4. 官方工程图风格：设备使用中性外壳、内框、角部固定件；方形供电设施使用圆形示意外壳，网格占地保持原样。已设置取货 / 过滤材料的设施显示已有 ItemIcon；其他设施仍显示原分类符号及名称。端口槽来自原真实端口与连接状态，不额外生成装饰端口。物流带改为浅黄色，管道为中性对比色，方向箭头缩小且保持真实流向。选择、框选、断电、关闭、地图冲突与阻塞提示保留。

## 动画与边界

等高线来自固定多峰高度场，路径只生成一次；绘制时缓慢平移，默认最多每秒 20 次刷新。页面离开、App 非前台或低电量模式时暂停；减少动态效果时静态显示。不添加交互，不接收触摸，不进入 VoiceOver 树。实际功耗、帧率与对比度尚未测量。

浅 / 深色跟随系统，不读写或改变用户的存档、外观偏好和其他设置。图形占地、端口位置、碰撞范围与点按区域不变；圆形示意不改变方形网格占地规则。

## 本批文件

新增：

- `EndfiledPlanner/DesignSystem/Components/AppTopographicBackground.swift`
- `EndfiledPlanner/ProductionOptimizer/View/FactoryBuildingShell.swift`
- `EndfiledPlanner/ProductionOptimizer/View/FactoryTelemetryFrame.swift`

修改：

- `EndfiledPlanner/DesignSystem/AppTheme.swift`
- `EndfiledPlanner/ProductionOptimizer/View/FactoryCanvasPalette.swift`
- `EndfiledPlanner/ProductionOptimizer/View/FactoryGridView.swift`
- `EndfiledPlanner/ProductionOptimizer/View/FactoryLayoutView.swift`
- `EndfiledPlanner/other/HomeView.swift`
- `EndfiledPlanner/other/SettingsView.swift`
- `EndfiledPlanner/RecipeSearch/View/SearchView.swift`
- `EndfiledPlanner/RecipeSearch/View/RecipeDetailView.swift`
- `EndfiledPlanner/BluePrint/View/BlueprintSetView.swift`
- `EndfiledPlanner/BluePrint/View/BlueprintSetDetailView.swift`
- `docs/UI_DESIGN_SYSTEM.md`、`docs/UI_REDESIGN_PLAN.md` 及本交接文档。

未编辑 Model、ViewModel、Service、模拟器公式、连接规则、数据包、存档 / 持久化键、项目签名或发布设置；没有新增第三方库。

## 用户验证建议

- 先构建，再在系统日 / 夜间模式切换，检查基建纸面、设备字、端口与物流 / 管道箭头的可读性。
- 查看利用率开 / 关、图例与部分负载标牌；确认统计入口、满载与瓶颈状态仍可辨认。
- 观察其他主页与详情的底纹，进入基建确认没有等高线；开减少动态效果、切后台、切标签查看暂停行为。
- 复核原连线 / 放置 / 移动 / 旋转 / 材料选择操作、iPad 分屏和低缩放时端口可辨认性。
- 检查日间模式下旧页面剩余局部固定色、正文对比度、辅助字号与长文本。此次没有全面重写配方 / 社区蓝图内容组件，仍可能有后续样式细节需要根据运行反馈调整。

## 用户反馈修正 · 同日

- 等高线级别由 19 增至 38，采样精度同步提高；减小背景放大系数，将主 / 次线宽由 0.9 / 0.6pt 收紧为 0.6 / 0.35pt，缓解线间距大、图案过宽的问题。
- 撤回浮动控件的切角轮廓与双行开关样式，恢复小圆角单行入口，明确标为“线的利用率”。删除本批新增且已不使用的 `FactoryTelemetryFrame.swift`。
- 科技化样式改在线路本身：满载 / 瓶颈为绿色 / 红色分段细线；部分负载增加蓝色分段细线、十格刻度及原真实百分比。刻度按已有 ratio 绘制，不改变分类阈值、流量或计算公式。
- 所有设备外壳和内框恢复标准矩形，不再使用切角内框。供电设施仍为方形外壳，圆环仅在内部绘制。

这次仍未构建、运行或测试；请用户重点查看等高线密度、线路刻度在不同缩放下的可读性，以及供电桩的方壳 / 圆环位置。
