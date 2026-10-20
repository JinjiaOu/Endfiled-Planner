# 基建工业终端视觉稿 · 实施交接

日期：2026-10-20。用户确认视觉稿后实施。

**按用户要求，代理没有执行构建、运行、Preview、截图或测试。以下是实现范围，不能视为编译、视觉或交互验证通过。未提交 Git Commit。**

## 本批实现

- 深色主题由蓝灰 / 金黄调整为石墨灰 / 浅柠檬黄。共享组件同步采用小圆角，保留浅色与增强对比度分支，不改变用户外观设置。
- 上下文栏优先单行显示地图和编辑模式，空间不足时换为两行；撤销、重做、保存保留。
- iPhone：建筑和线路检查器默认显示标题、状态摘要、明确的展开入口以及操作行。协议核心保留发电与供电范围说明，展开可访问所有原出货口和运行详情。建筑动作改为一行四项，辅助字号下两列。移动操作会展开说明。
- iPad：常规宽度且工作区至少 760pt 宽、520pt 高时，使用 304pt 常驻侧栏。辅助字号需要至少 1000pt 宽，侧栏为 360pt；尺寸不足时回到底部面板。侧栏实际参与布局，画布和底部工具栏位于左侧，统计 / 利用率入口不再用固定偏移避让浮层。未选中对象时显示选择说明与建造入口。
- 宽屏工具栏在工作区宽度至少 1000pt 时采用横排图文；手机保留单行工具、上下图文。工具状态与原 ViewModel 操作保持一致。
- 检查器为平直分区，普通尺寸的标题与操作位于配置滚动区之外。低高度 / 辅助字号时允许整个面板滚动并裁切，保留底部滚动余量。
- 协议核心的出货口改为细分隔列表，保留材料图标、整行点击、真实朝向标签、材料选择与“不出货”，补充 VoiceOver 标签；长材料名称允许增高。
- 画布底色调整为中性深石墨色。建筑分类、端口、线路与利用率含义沿用原映射。

## 修改文件

- `EndfiledPlanner/DesignSystem/AppTheme.swift`
- `EndfiledPlanner/DesignSystem/Components/AppInspectorContainer.swift`
- `EndfiledPlanner/ProductionOptimizer/View/FactoryCanvasPalette.swift`
- `EndfiledPlanner/ProductionOptimizer/View/FactoryWorkspaceToolbar.swift`
- `EndfiledPlanner/ProductionOptimizer/View/FactoryLayoutView.swift`
- `EndfiledPlanner/ProductionOptimizer/View/BuildingDetailPanel.swift`
- `EndfiledPlanner/ProductionOptimizer/View/BeltDetailPanel.swift`
- `docs/UI_DESIGN_SYSTEM.md`
- `docs/UI_REDESIGN_PLAN.md`
- 本交接文档。

本批未编辑 ViewModel、Model、Service、模拟计算、存档格式、持久化键、签名或发布配置。既有未提交修改保留。

## 交给用户验证

1. 构建项目，查看 iPhone 上的默认摘要、展开 / 收起、关闭和底部边界；展开后滚动至最后一段说明。
2. 协议核心各出货口选择 / 清空材料、旋转后标签、普通机器配方与状态、关闭 / 开启、移动 / 取消、收纳；核心的原收纳限制仍由原逻辑处理。
3. 建筑长按拖入、画布缩放 / 滚动、线路绘制、框选、布局放置、保存、撤销 / 重做、统计和利用率入口。
4. iPad 横竖屏、分屏和窗口尺寸变化：侧栏与画布不重叠，工具栏只占左侧；窄窗口回到底部。尤其关注重排后的拖拽落点与边缘自动滚动。
5. 辅助字号、长材料名、横屏低高度和 VoiceOver；深浅色、增强对比度、减少动态效果。共享颜色和圆角也会影响此前接入设计系统的页面。

本批只落实已认可的基建视觉方向，其他模块的完整页面重设计仍待继续；应先结合用户实际运行反馈决定下一批。
