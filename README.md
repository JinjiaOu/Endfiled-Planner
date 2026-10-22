<div align="center">

<img src="%E7%B4%A0%E6%9D%90%E5%8E%9F%E5%9B%BE/AppIcon%E5%8E%9F%E5%9B%BE.png" width="128" alt="Endfield Planner 图标">

# Endfield Planner · 终末地生产规划

**《明日方舟：终末地》玩家自制的生产规划工具（iOS / iPadOS）**

基建布局规划与产能模拟 · 目标产量计算 · 配方链分析 · 社区蓝图码收录

![iOS 26+](https://img.shields.io/badge/iOS-26%2B-black?logo=apple)
![SwiftUI](https://img.shields.io/badge/SwiftUI-orange?logo=swift&logoColor=white)
![地图](https://img.shields.io/badge/地图-四号谷地%20%7C%20武陵-yellow)

[GitHub](https://github.com/JinjiaOu/Endfiled-Planner) · [Gitee（国内镜像）](https://gitee.com/JinjiaOu/endfield--planner)

</div>

---

## 截图

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/home.webp" width="200" alt="首页"><br><sub>首页</sub></td>
    <td align="center"><img src="docs/screenshots/factory_utilization.webp" width="200" alt="基建规划·利用率视图"><br><sub>基建规划 · 利用率视图</sub></td>
    <td align="center"><img src="docs/screenshots/factory_highlight.webp" width="200" alt="基建规划·点产物高亮"><br><sub>基建规划 · 点产物高亮</sub></td>
    <td align="center"><img src="docs/screenshots/factory_stats.webp" width="200" alt="基建规划·产能统计"><br><sub>基建规划 · 产能统计</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/screenshots/calculator.webp" width="200" alt="产量计算"><br><sub>产量计算</sub></td>
    <td align="center"><img src="docs/screenshots/recipe_tree.webp" width="200" alt="配方树"><br><sub>配方分析 · 配方树</sub></td>
    <td align="center"><img src="docs/screenshots/blueprints.webp" width="200" alt="社区蓝图"><br><sub>社区蓝图 · 蓝图集详情</sub></td>
    <td></td>
  </tr>
</table>

<p align="center">
  <img src="docs/screenshots/factory_export.webp" width="640" alt="导出的整张布局图"><br>
  <sub>导出的整张布局图：内置武陵预设「灼铜装备原件」，右侧是水泵区</sub>
</p>

---

## 功能

### 🧮 产量计算
- 选一个产物、填每分钟要多少个，沿配方往上游反推**每一级要几台什么机器**、原料各要多少、总耗电
- 同一物品在多条分支里的需求自动合并；有多条配方的物品可以切换；任何一级都能改成"从仓库取"不再展开
- 矿石、作物默认按仓库原料算，水和气默认算成水泵、气泵台数；原料附带大约要几条传送带 / 管道，副产物单独列出

### 🔍 配方分析系统
- 搜索物品（带联想和搜索历史）或从完整物品列表里挑选，设定目标数量，展开完整的**生产配方树**
- 自动挑选最合适的配方（优先避开互相依赖的循环配方），显示每一级所需原料数量和耗时
- 配方树可缩放浏览，适合规划一条产线到底要准备多少原料

### 📋 社区蓝图
- 收录社区作者分享的基建蓝图码，按**四号谷地 / 武陵**分区，可按作者搜索
- 每套蓝图带说明：产物、消耗、效率、占地、摆放顺序和注意事项，一键复制蓝图码
- 数据放在仓库里的 [`blueprints.json`](EndfiledPlanner/BluePrint/blueprints.json)，App 优先从 Gitee / GitHub 读取最新版，**更新蓝图不需要发新版 App**，在蓝图页点刷新即可拿到

### 🏭 基建规划（生产优化模块）
在网格画布上自由摆放建筑、拉传送带和管道，App 会实时模拟整套基建的稳定产能。

**摆放与编辑**
- 建筑数据、端口位置、配方均来自游戏数据表；建造面板按分类筛选，按住拖到画布放置
- 画面按官方蓝图风格绘制：建筑中央显示当前配方的产物，端口是沿边缘的槽位，分流器 / 汇流器 / 物流桥 / 准入口各有专用符号
- 画传送带 / 管道：拖动即走 L 形路线，自动吸附建筑端口，同类线十字交叉自动放物流桥
- 移动、旋转建筑时，接在它身上的线会跟着重新走线
- **框选**一组建筑和线，整组移动 / 删除；拖到画面边缘自动滚动
- **我的布局**：把框选的一组存成布局（带全部配方和设置），之后可整组放到任意位置、整体旋转，跨地图放置会提前提醒冲突
- 完整的撤销 / 重做；双指缩放，进入时缩到全图并以协议核心为中心
- **导出布局图片**：整张画布裁到有内容的区域，存相册或分享
- 内置**使用指南**，说明操作方式和跟游戏不一样的简化规则

**产能模拟**
- 按带速 / 管速、分流器（堵住一路会匀给其它路）、汇流器、准入口（限速 + 只放行某种物品）逐级推算每台机器的实际运行率
- 机器状态一目了然：生产中 / 原料不足 / 阻塞 / 未激活，并给出原因（比如"被物品准入口挡住（只放行 B）"）
- 反应池、扩容反应池的多配方自我供给；转化机、气体散布机的激活与环境
- 电力：供电桩覆盖范围、热能池按燃料算发电、协议核心固定发电；电力不足或建筑没通电时画布上直接提示
- 仓库取货口 / 存货口、地下暗管、协议核心出货口（每个口单独选出什么）
- **利用率视图**：传送带和管道按流量 / 上限上色，跑满、没跑满（标百分比）、空闲、被限流（瓶颈）一眼看出
- 产能统计：总产出、总消耗、耗电与发电、瓶颈建筑；**点一个产物，画布上生产、消耗、运送它的机器和线高亮**，其余变暗

**地图规则**
- 四张画布，大小取自游戏数据里各基地的满级范围：四号谷地主基地 70×70、小基地 40×40，武陵主基地 80×80、小基地 50×50
- 四号谷地与武陵分别按游戏规则限制：武陵专属建筑、四号谷地只能用基础模式配方、四号谷地不能用管道
- 仓库取线：四号谷地贴着基地边上的固定存取线（主基地半圈、小基地一条边）；武陵贴仓库存取线源桩 / 基段，基段连通源桩即可，能拐弯、分叉
- 武陵基地右侧有单独的**水泵区**：水泵、气泵放在这里，出口朝向基地，默认通电（水池、酸池、息壤气口在游戏里都在基地外）
- 规则随时重新检查，不合规的建筑会标红并不参与计算
- 内置两套预设产线（四号谷地高容电池、武陵灼铜装备原件），生成时校验过摆放、连线和满载，可一键载入参考

### ⚙️ 其他
- **游戏数据在线更新**：配方、物品、建筑和图标可以在设置里检查更新，下载后重启生效，不用等新版 App
- **App 内反馈**：设置 → Report Issue，写几句话、附截图就能发出，不需要注册账号或邮箱（走 iCloud）；也可以选 GitHub Issues

---

## 构建与运行

需要支持 iOS 26 SDK 的 Xcode。

```bash
git clone https://github.com/JinjiaOu/Endfiled-Planner.git
cd Endfiled-Planner
open EndfiledPlanner.xcodeproj
```

选择 `EndfiledPlanner` scheme 和 iPhone / iPad 模拟器（或真机），运行即可。项目没有第三方依赖。

> 在 Xcode 里运行时首次打开会稍慢（调试器附着 + 首次启动），从桌面直接打开不受影响。

---

## 项目结构

```
EndfiledPlanner/
├── Calculator/              产量计算：反推机器台数 / 原料 / 耗电
├── RecipeSearch/            配方分析：配方数据加载、物品目录、配方树视图
├── BluePrint/               社区蓝图：blueprints.json 及远端加载、缓存
├── ProductionOptimizer/     基建规划
│   ├── ViewModel/           网格模型、产能模拟器（FlowSimulator）、地图规则（MapRules）、
│   │                        框选 / 我的布局 / 放置等
│   └── View/                画布、建造面板、建筑与管线详情、产能统计、导出图片、使用指南
├── DataPack/                游戏数据在线更新
├── DesignSystem/            颜色、字体、通用组件
└── other/                   App 入口、首页、设置、反馈；游戏数据 JSON 与物品图标

Tools/                       数据与资源生成脚本（Python）
├── gen_datapack.py          从游戏解包表格生成 devices / recipes / items / fuels 等 JSON
├── gen_icons.py             生成物品图标资源目录
├── gen_presets.py           复刻 App 的摆放与模拟规则，生成并校验内置预设产线
├── presetlib.py             上面脚本用到的规则复刻（改模拟规则时要同步）
└── blueprint_import/        把社区蓝图表格（xlsx）整理进 blueprints.json
```

## 数据来源

- 建筑、配方、物品、燃料等数据由 `Tools/gen_datapack.py` 从游戏解包的数据表生成（解包数据本身不包含在仓库里）
- 带速、管速、供电范围、发电量等数值取自数据表，并在游戏内实测核对
- 蓝图码来自社区作者的公开分享，作者署名保留在每套蓝图上

## 投稿蓝图

蓝图数据就是 [`EndfiledPlanner/BluePrint/blueprints.json`](EndfiledPlanner/BluePrint/blueprints.json)。想补充或修正蓝图，欢迎提 Issue 或 Pull Request（也可以在 App 里用反馈发给我），注明蓝图名称、蓝图码、作者和适用地图。合并后所有用户在蓝图页刷新就能看到。

---

## 致谢

感谢以下作者公开分享蓝图（排名不分先后）：MSC、萧然Q、魔法Zc目录、流星飞、亚历山大个锤子 / 帝江攻略组、自在道爷，以及 App 内注明的各模块作者。

## 免责声明

本项目为玩家自制的非官方工具，与鹰角网络（Hypergryph）及《明日方舟：终末地》官方无任何关联。游戏名称、数据、图标等相关内容的版权归其各自所有者所有。蓝图版权归原作者所有，如有侵权或希望移除，请提 Issue 联系。
