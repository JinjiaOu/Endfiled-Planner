// Created by Jinjia Ou on 10/21/26.

import SwiftUI

/// 基建规划使用指南：基本操作、跟游戏不一样的简化规则、画布上各种标记怎么看
struct FactoryGuideView: View {
    @Environment(\.dismiss) private var dismiss

    private struct Section: Identifiable {
        let id = UUID()
        let title: String
        let symbol: String
        let items: [String]
    }

    private let sections: [Section] = [
        Section(title: "基本操作", symbol: "hand.tap", items: [
            "底部工具栏切换模式：选择、建造、传送带、管道（仅武陵）、框选、我的布局、删除。",
            "建造：打开建造面板，长按设施拖进画布；放置前可以先旋转。",
            "画线：在传送带/管道模式下，按住从起点拖到终点，线走 L 形；也可以先点起点、再点终点。",
            "删除：删除模式下点一下删一个，按住划过去连着删。",
            "框选：拉框选中一片，按住选中的建筑可以整组拖走；选中后可以存成“我的布局”。",
            "双指缩放画布；顶部可以撤销、重做、保存画布。右上角“…”里能切换地图、加载预设、导出图片、清空布局。",
        ]),
        Section(title: "跟游戏不一样的地方", symbol: "exclamationmark.triangle", items: [
            "武陵水泵区：基地右侧单独一条 3 格宽的区域，水泵、二型耐酸水泵、气体收集泵只能放这里，出口朝向基地；这里的泵默认通电，不用放供电桩，区域里不能走线。",
            "四号谷地外围的仓库存取线只是示意，不占格子；取货口/存货口贴着基地上边、左边放。",
            "武陵仓库存取线：基段贴着源桩，或贴着已经连到源桩的基段就行，可以拐弯、往几个方向分，数量不限。",
            "暗管不模拟两头的连通：暗管出口自己选出什么液体或气体，相当于一个源头；暗管入口只是把东西送走。",
            "同类型的线十字交叉会自动补物流桥/管道桥；传送带和管道可以叠在同一格（管道变细画在上面）。",
            "电力：建筑跟任一供电桩的范围（本体向四周扩几格，选中供电桩时会显示）有重叠就算通电；发电不够只在顶部提示，不会让机器降速。",
            "产能按稳定满速估算，不算启动过程和库存；分流器平均分给各路，某一路堵住会匀给其他路。",
        ]),
        Section(title: "看懂画布", symbol: "eye", items: [
            "建筑右上角圆点：绿色生产中，红色阻塞（产物送不出去），橙色原料不足，灰色未激活或没选配方。",
            "左上角闪电划线图标：不在供电桩范围内，不运行。红框：这张地图不支持这个建筑或配方，点开详情看原因。",
            "建筑中央的物品图标是当前配方的主产物，画布缩到很小时会隐藏。",
            "建筑边缘的长条槽是端口，箭头是物流方向；接上线后槽外沿出现一条带颜色的短条。",
            "分流器：一进三出，中间菱形；汇流器：三进一出，中间圆点；物流桥：十字立交，竖的从横的上面跨过去；准入口：直通加一道闸门，右下角小图标是只放行的物品。箭头实色表示这个方向接上了线。",
            "线上的小箭头是流向；整条线标红表示穿过了建筑。",
        ]),
        Section(title: "统计与分析", symbol: "chart.bar", items: [
            "右下角“统计”打开产能统计：电力余量、未满载的机器和原因、产出和消耗汇总。",
            "在统计里点一个产物，画布上生产、消耗、运送它的机器和线保持亮着，其余变暗；点顶部提示条的 × 取消。",
            "“线的利用率”开关：线按流量分档上色，空闲变暗、跑满绿色、被限流红色，其余标百分比。",
            "想先算要几台机器，可以用首页的“产量计算”。",
        ]),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                AppPageHeader(title: "基建规划指南", subtitle: "画布上的规则是按游戏简化过的，下面列出了操作方式和不一样的地方。")
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Label(section.title, systemImage: section.symbol)
                            .font(AppTypography.sectionTitle)
                            .foregroundStyle(AppColors.primaryText)
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            ForEach(section.items, id: \.self) { item in
                                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
                                    Circle().fill(AppColors.accent).frame(width: 5, height: 5)
                                        .accessibilityHidden(true)
                                    Text(item)
                                        .font(AppTypography.body)
                                        .foregroundStyle(AppColors.primaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(AppSpacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: AppRadius.surface))
                    }
                }
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.md)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("使用指南")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") { dismiss() }
            }
        }
        .appPageStyle()
    }
}

#Preview {
    NavigationStack { FactoryGuideView() }
}
