#!/usr/bin/env python3
"""生成 App 内置的两套预设产线（存档格式 JSON，打进 bundle），并在生成时校验：
摆放合法、每条线两头都接在预期的口上、流量模拟里主产线机器全部满载。

- 四号谷地：高容谷地电池，1 台封装机满载（1 个/分钟），原料从仓库取 源矿/蓝铁矿/砂叶
- 武陵：灼铜装备原件，1 台装备原件机满载（6 个/分钟），原料从仓库取 赤铜矿/稳定碳块，其余靠水泵/气泵

运行：python3 Tools/gen_presets.py [--ascii]
"""
import argparse
import json
import sys

import presetlib as P
from presetlib import UP, RIGHT, DOWN, LEFT


# MARK: - 四号谷地：高容谷地电池
#
# 配比（每条带 30/分钟）：
#   封装机 1 台：钢制零件 60 + 致密源石粉末 90 → 高容谷地电池 1/分钟
#   钢制零件：蓝铁矿 →精炼炉→ 蓝铁块 →粉碎机→ 蓝铁粉末，2 条蓝铁粉末 + 1 条砂叶粉末 →研磨机→ 致密蓝铁粉末
#             →精炼炉→ 钢块 →配件机→ 钢制零件。2 组，共 4 条蓝铁矿
#   致密源石粉末：源矿 →粉碎机→ 源石粉末，2 条 + 1 条砂叶粉末 →研磨机→ 致密源石粉末。3 组，共 6 条源矿
#   砂叶粉末：5 台研磨机共要 150/分钟，1 台粉碎机吃 30 砂叶出 90 砂叶粉末，所以 2 台：
#             一台满载出 3 条，另一台只接 2 条出口，跑 2/3（比例本身凑不成整数，这是唯一不满载的机器）
# 整体从上往下流：取货口全在上边，机器都朝下（入口在上、出口在下），成品走左边存货口

def build_valley4():
    L = P.Layout('valley4_battery', 'valley4')

    def outlet(col, material):
        return L.place('unloader_1', col, 0, DOWN, material=material, label=f'取货口·{material}')

    def feed(src, src_cell, dst, dst_cell, via=None):
        """src 在 src_cell 的物品出口 → dst 在 dst_cell 的物品入口"""
        return L.connect(src, L.port_at(src, 'item', 'output', src_cell),
                         dst, L.port_at(dst, 'item', 'input', dst_cell), via=via)

    def ore_lane(c, ore):
        """一条矿石线：取货口(c..c+2, 0) → [精炼炉] → 粉碎机，返回 (粉碎机, 出口格)"""
        out = outlet(c, ore)
        if ore == '蓝铁矿':
            furnace = L.place('furnance_1', c, 3, DOWN, recipe='furnance_iron_nugget_1', label='精炼炉·蓝铁块')
            feed(out, (c + 1, 0), furnace, (c + 1, 3))
            grinder = L.place('grinder_1', c, 8, DOWN, recipe='grinder_iron_powder_1', label='粉碎机·蓝铁粉末')
            feed(furnace, (c + 1, 5), grinder, (c + 1, 8))
            return grinder, (c + 1, 10)
        grinder = L.place('grinder_1', c, 3, DOWN, recipe='grinder_originium_powder_1', label='粉碎机·源石粉末')
        feed(out, (c + 1, 0), grinder, (c + 1, 3))
        return grinder, (c + 1, 5)

    # 5 组研磨机（每组吃 2 条矿粉 + 1 条砂叶粉末），中间夹着砂叶粉碎机
    groups = [  # (起始列, 矿石, 研磨机配方, 砂叶粉末从哪个入口进)
        (2, '蓝铁矿', 'thickener_iron_enr_powder_1', 5),
        (8, '蓝铁矿', 'thickener_iron_enr_powder_1', 5),
        (20, '源矿', 'thickener_originium_enr_powder_1', 0),
        (26, '源矿', 'thickener_originium_enr_powder_1', 0),
        (32, '源矿', 'thickener_originium_enr_powder_1', 0),
    ]
    mills = []
    for c, ore, recipe, moss_port in groups:
        lane_a = ore_lane(c, ore)
        lane_b = ore_lane(c + 3, ore)
        name = '致密蓝铁粉末' if ore == '蓝铁矿' else '致密源石粉末'
        mill = L.place('thickener_1', c, 16, DOWN, recipe=recipe, label=f'研磨机·{name}')
        feed(*lane_a, mill, (c + 1, 16))
        feed(*lane_b, mill, (c + 4, 16))
        mills.append((mill, c, c + moss_port))

    # 砂叶：左边一台只接 2 条出口给两组蓝铁，右边一台满载 3 条给三组源石
    moss_out_l = outlet(14, '砂叶')
    moss_l = L.place('grinder_1', 14, 3, DOWN, recipe='grinder_plant_moss_powder_3_1', label='粉碎机·砂叶粉末(2/3)')
    feed(moss_out_l, (15, 0), moss_l, (15, 3))
    moss_out_r = outlet(17, '砂叶')
    moss_r = L.place('grinder_1', 17, 3, DOWN, recipe='grinder_plant_moss_powder_3_1', label='粉碎机·砂叶粉末')
    feed(moss_out_r, (18, 0), moss_r, (18, 3))

    # 砂叶粉末分配：离得远的走上面一行，离得近的走下面一行，互相不交叉，只跨过中间组的矿粉线（补物流桥）
    feed(moss_l, (14, 5), mills[0][0], (mills[0][2], 16), via=[(14, 12), (mills[0][2], 12)])
    feed(moss_l, (15, 5), mills[1][0], (mills[1][2], 16), via=[(15, 13), (mills[1][2], 13)])
    feed(moss_r, (19, 5), mills[4][0], (mills[4][2], 16), via=[(19, 12), (mills[4][2], 12)])
    feed(moss_r, (18, 5), mills[3][0], (mills[3][2], 16), via=[(18, 13), (mills[3][2], 13)])
    feed(moss_r, (17, 5), mills[2][0], (mills[2][2], 16), via=[(17, 14), (mills[2][2], 14)])

    # 致密蓝铁粉末 → 精炼炉(钢块) → 配件机(钢制零件)
    parts = []
    for mill, c, _ in mills[:2]:
        steel = L.place('furnance_1', c + 1, 22, DOWN, recipe='furnance_iron_enr_1', label='精炼炉·钢块')
        feed(mill, (c + 2, 19), steel, (c + 2, 22))
        comp = L.place('component_mc_1', c + 1, 27, DOWN, recipe='component_iron_enr_cmpt_1', label='配件机·钢制零件')
        feed(steel, (c + 2, 24), comp, (c + 2, 27))
        parts.append((comp, (c + 2, 29)))

    # 封装机：5 条线按左右顺序接进上边 5 个入口
    packer = L.place('tools_assebling_mc_1', 18, 34, DOWN, recipe='tools_proc_battery_3_1', label='封装机·高容谷地电池')
    feed(parts[0][0], parts[0][1], packer, (18, 34), via=[(4, 32), (18, 32)])
    feed(parts[1][0], parts[1][1], packer, (19, 34), via=[(10, 31), (19, 31)])
    feed(mills[2][0], (22, 19), packer, (20, 34), via=[(22, 30), (20, 30)])
    feed(mills[3][0], (28, 19), packer, (21, 34), via=[(28, 31), (21, 31)])
    feed(mills[4][0], (34, 19), packer, (22, 34), via=[(34, 32), (22, 32)])

    inlet = L.place('loader_1', 0, 40, RIGHT, label='存货口·高容谷地电池')
    feed(packer, (18, 37), inlet, (0, 41))

    L.place('sp_hub_1', 45, 20, UP, label='协议核心')
    L.finish()
    return L, {'粉碎机·砂叶粉末(2/3)', '取货口·砂叶'}


def build_wuling():
    """武陵布局在 preset_wuling.py：主产线位置写死，辅助机器（水泵、分流器、气泵等）的位置
    来自 wuling_layout.json，由 `python3 preset_wuling.py search ...` 搜索得到"""
    import preset_wuling as W
    mv = json.loads((P.ROOT / 'Tools' / 'wuling_layout.json').read_text())
    f, _, layout = W.score(mv)
    if f:
        print('  武陵布线失败:', layout.failures)
    partial = {'水泵·清水(半载)', '二型耐酸水泵·液化息壤(激活)', '二型耐酸水泵·沉积酸', '液气转化机·酸气',
               '气体收集泵·息壤气', '气体收集泵·息壤气(激活)', '气体收集泵·惰气'}
    return layout, partial


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--ascii', action='store_true')
    args = ap.parse_args()
    failed = False
    for builder, filename in ((build_valley4, 'preset_valley4_battery.json'), (build_wuling, 'preset_wuling_equip.json')):
        layout, partial = builder()
        if args.ascii:
            print(layout.ascii())
        sim = P.simulate(layout)
        bad_links, not_full = P.report(layout, sim, expect_partial=partial)
        if bad_links or not_full or not sim['converged']:
            failed = True
            continue
        (P.OTHER / filename).write_text(json.dumps(layout.to_json(), ensure_ascii=False, indent=1) + '\n')
        print(f'  wrote {filename}')
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
