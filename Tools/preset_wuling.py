"""武陵预设（灼铜装备原件）的布局。主产线机器位置写死在 build() 里；
水泵、分流器、气泵、散布机等辅助机器的位置/朝向放在 wuling_layout.json，
由局部搜索得到（布线失败数最少，其次总线长最短）：

    python3 preset_wuling.py search <迭代次数> <随机种子> [起始坐标.json]

最后一行输出就是新的坐标，覆盖 wuling_layout.json 后运行 gen_presets.py 重新生成预设。
"""
import json
import random
import sys

import presetlib as P
from presetlib import UP, RIGHT, DOWN, LEFT

# 辅助机器的位置/朝向（可被 search() 调整），主产线机器写死在 build() 里
MOVABLE = {
    'W4': ['pump_1', 26, 5, RIGHT], 'W7': ['pump_1', 34, 5, RIGHT],
    'W5': ['pump_1', 34, 13, UP], 'S5': ['log_pipe_splitter', 38, 13, UP],
    'W6': ['pump_1', 55, 13, UP],
    'HC': ['log_converger', 36, 22, DOWN], 'WD': ['winder_1', 34, 25, DOWN], 'MS': ['log_hongs_bus_source', 34, 31, UP],
    'CvR': ['log_pipe_converger', 19, 18, LEFT], 'GR1': ['gas_pump_1', 21, 17, DOWN], 'GR2': ['gas_pump_1', 21, 20, DOWN],
    'V': ['vaporizer_1', 13, 15, DOWN], 'T': ['transmuter_1', 18, 12, UP], 'A': ['pump_2', 24, 12, UP], 'L2': ['pump_2', 24, 16, UP],
    'GA': ['gas_pump_1', 0, 12, UP], 'SA': ['log_pipe_splitter', 4, 13, UP],
    'GI1': ['gas_pump_1', 23, 27, UP], 'GI2': ['gas_pump_1', 23, 23, UP], 'CvI': ['log_pipe_converger', 19, 26, DOWN],
    'W1': ['pump_1', 5, 34, UP], 'S1': ['log_pipe_splitter', 8, 37, DOWN],
    'W2': ['pump_1', 21, 34, UP], 'S2': ['log_pipe_splitter', 24, 37, DOWN],
    'W3': ['pump_1', 43, 32, UP], 'S3': ['log_pipe_splitter', 46, 37, DOWN],
    'L1': ['pump_2', 47, 31, UP], 'SL': ['log_pipe_splitter', 51, 33, UP],
    'C': ['component_mc_1', 3, 8, LEFT], 'S': ['shaper_1', 18, 22, LEFT],
}
RECIPES = {'W7': 'pump_1:0', 'W4': 'pump_1:0', 'W5': 'pump_1:0', 'W6': 'pump_1:0', 'W1': 'pump_1:0', 'W2': 'pump_1:0', 'W3': 'pump_1:0',
           'GR1': 'gas_pump_1:1', 'GR2': 'gas_pump_1:1', 'GA': 'gas_pump_1:1', 'GI1': 'gas_pump_1:0', 'GI2': 'gas_pump_1:0',
           'T': 'liquid_transmuter_1_gas_gas_acid_1', 'A': 'pump_2:8', 'L2': 'pump_2:4', 'L1': 'pump_2:4',
           'WD': 'winder_equip_script_4_3', 'C': 'component_copper_enr2_cmpt_1', 'S': 'shaper_gas_copper_jar_1'}
LABELS = {'W7': '水泵·清水(半载)', 'W4': '水泵·清水(半载)', 'W5': '水泵·清水', 'W6': '水泵·清水(半载)', 'W1': '水泵·清水', 'W2': '水泵·清水', 'W3': '水泵·清水',
          'S5': '管道分流器', 'S1': '管道分流器', 'S2': '管道分流器', 'S3': '管道分流器', 'SA': '管道分流器', 'SL': '管道分流器',
          'HC': '汇流器', 'CvR': '管道汇流器', 'CvI': '管道汇流器', 'MS': '仓库存取线源桩',
          'WD': '装备原件机·灼铜装备原件', 'GR1': '气体收集泵·息壤气', 'GR2': '气体收集泵·息壤气',
          'V': '气体散布机·酸性环境', 'T': '液气转化机·酸气', 'A': '二型耐酸水泵·沉积酸', 'L2': '二型耐酸水泵·液化息壤(激活)',
          'GA': '气体收集泵·息壤气(激活)', 'GI1': '气体收集泵·惰气', 'GI2': '气体收集泵·惰气',
          'L1': '二型耐酸水泵·液化息壤', 'C': '配件机·灼铜零件', 'S': '塑形机·赤铜耐压罐'}


def build(mv=None, soft=True, first_nets=None):
    mv = mv or MOVABLE
    L = P.Layout('wuling_equip', 'wuling')
    L.soft = soft
    place = L.place
    bad = []

    def ports(b, kind, io):
        return [p for p in b.device.ports if p.kind == kind and p.io == io]

    def first(b, kind, io, edge=None):
        """1x1 的分流器/汇流器按未旋转时的边取口，其它建筑取该类型第一个口"""
        if edge is not None:
            return L.pp(b, kind, io, edge, 0)
        return ports(b, kind, io)[0]

    def conn(src, dst, kind='item', s=None, d=None, se=None, de=None, via=None):
        if src is None or dst is None:
            L.failures.append('missing building')
            return None
        try:
            sp, dp = L.best_pair(src, dst, kind, s, d, se, de)
        except KeyError as e:
            L.failures.append(f'port {e}')
            return None
        return L.connect(src, sp, dst, dp, via=via)

    def pipe(src, dst, **kw):
        return conn(src, dst, 'pipe', **kw)

    def mplace(name):
        dev, x, y, rot = mv[name]
        try:
            b = place(dev, x, y, rot, recipe=RECIPES.get(name), label=LABELS[name])
        except P.PlacementError:
            bad.append(name)
            return None
        return b

    # ===== 固定：上方仓库线 + 天有洪炉·息壤 ×5 =====
    ts1 = place('log_hongs_bus_source', 20, 0); ts2 = place('log_hongs_bus_source', 40, 0)
    tl1 = place('log_hongs_bus', 12, 0, RIGHT); tr1 = place('log_hongs_bus', 24, 0, RIGHT)
    tl2 = place('log_hongs_bus', 32, 0, RIGHT); tr2 = place('log_hongs_bus', 44, 0, RIGHT)
    ovens, oven_docks = [], []
    for x, docks in zip([13, 21, 29, 38, 45], [[(tl1, 0), (tl1, 3)], [(ts1, 0), (tr1, 0)], [(tr1, 5), (tl2, 0)],
                                               [(tl2, 5), (ts2, 1)], [(tr2, 0), (tr2, 3)]]):
        ov = place('xiranite_oven_1', x, 7, DOWN, recipe='xiranite_oven_xiranite_powder_1', label='天有洪炉·息壤')
        for seg, off in docks:
            oven_docks.append((L.dock('unloader_1', seg, DOWN, off, material='稳定碳块', label='取货口·稳定碳块'), ov))
        ovens.append(ov)
    O1, O2, O3, O4, O5 = ovens
    H1 = place('xiranite_oven_1', 25, 15, DOWN, recipe='xiranite_oven_xiranite_enr_powder_1', label='天有洪炉·重息壤')
    H2 = place('xiranite_oven_1', 42, 15, DOWN, recipe='xiranite_oven_xiranite_enr_powder_1', label='天有洪炉·重息壤')
    # ===== 固定：左侧铜链竖排，相邻机器端口直接对接 =====
    U = place('liquid_purifier_1', 7, 19, LEFT, recipe='liquid_purifier_gas_copper_enr_1', label='提纯机·气态赫铜')
    R = place('gas_reactor_1', 7, 13, LEFT, recipe='gas_reactor_gas_copper_enr2_1', label='气体反应炉·气态灼铜')
    B = place('transmuter_2', 7, 7, LEFT, recipe='liquid_transmuter_2_solid_copper_enr2_1', label='固气转化机·灼铜块')
    K = place('tools_assebling_mc_1', 13, 19, LEFT, recipe='tools_proc_filter_core_2', label='封装机·分离芯')
    E1 = place('transmuter_2', 2, 25, recipe='liquid_transmuter_2_gas_gas_copper_1', label='固气转化机·气态赤铜')
    E2 = place('transmuter_2', 11, 26, recipe='liquid_transmuter_2_gas_gas_copper_1', label='固气转化机·气态赤铜')
    # ===== 固定：下方赤铜矿仓库线 + 精炼炉模块 =====
    s1 = place('log_hongs_bus_source', 8, 44); s2 = place('log_hongs_bus_source', 32, 44); place('log_hongs_bus_source', 44, 44)
    g1 = place('log_hongs_bus', 0, 44, RIGHT); g2 = place('log_hongs_bus', 12, 44, RIGHT)
    g3 = place('log_hongs_bus', 24, 44, RIGHT); g4 = place('log_hongs_bus', 36, 44, RIGHT); g5 = place('log_hongs_bus', 48, 44, RIGHT)
    xs = [1, 9, 17, 25, 33, 47]
    furn, furn_docks = [], []
    for x, (seg, off) in zip(xs, [(g1, 0), (s1, 1), (g2, 5), (g3, 1), (s2, 1), (g5, 0)]):
        o = L.dock('unloader_1', seg, UP, off, material='赤铜矿', label='取货口·赤铜矿')
        f = place('furnance_1', x, 38, UP, recipe='furnance_copper_nugget_1', label='精炼炉·赤铜块')
        furn.append(f); furn_docks.append((o, f))
    F1, F2, F3, F4, F5, F6 = furn
    cls = [place('liquid_cleaner_1', x + 4, 38, label='废水处理机·污水') for x in xs[:4]]
    P1 = place('mix_pool_1', 37, 36, recipes=['pool_liquid_xiranite_poly_1'], label='反应池·壤晶废液')
    P2 = place('mix_pool_1', 51, 36, recipes=['pool_liquid_xiranite_poly_1'], label='反应池·壤晶废液')
    for pool in (P1, P2):
        pool.port_assignments = {6: '壤晶废液', 7: '惰性壤晶废液'}
    C5 = place('liquid_cleaner_1', 43, 38, label='废水处理机·惰性壤晶废液')
    C6 = place('liquid_cleaner_1', 57, 38, label='废水处理机·惰性壤晶废液')
    place('sp_hub_1', 50, 19, label='协议核心')
    # 电力：热能池贴着下方仓库线，燃料从基段上的取货口直接送进去
    import gen_presets
    fuel = gen_presets.pick_fuel(L, extra=sum(P.DEVICES[v[0]].power for v in mv.values()))
    fuel_out = L.dock('unloader_1', g4, UP, 0, material=fuel, label=f'取货口·{fuel}')
    station = place('power_station_1', 39, 41, RIGHT, label=f'热能池·{fuel}')

    # ===== 可调的辅助机器 =====
    m = {name: mplace(name) for name in MOVABLE}
    LD = None
    if m['MS'] is not None:
        try:
            LD = L.dock('loader_1', m['MS'], UP, 0, label='存货口·灼铜装备原件')
        except P.PlacementError:
            bad.append('LD')
    V = m['V']
    if V is not None:
        x0, x1, y0, y1 = V.bounds(); a0, a1, b0, b1 = R.bounds()
        if not (a1 >= x0 - 5 and a0 <= x1 + 5 and b1 >= y0 - 5 and b0 <= y1 + 5):
            bad.append('V-range')

    nets = []

    def add(fn, *args, **kw):
        nets.append((fn, args, kw))

    add(conn, fuel_out, station)

    # ===== 布线：先紧贴的，再主干，再辅助 =====
    for o, ov in oven_docks:
        add(conn, o, ov, d=(o.port_pos(o.device.ports[0])[0][0], 7))
    for o, f in furn_docks:
        add(conn, o, f, d=(o.port_pos(o.device.ports[0])[0][0], 40))
    for f, cl in zip(furn, cls):
        add(pipe, f, cl)
    add(pipe, F5, P1, d=(37, 39)); add(pipe, F6, P2, d=(51, 39))
    add(pipe, P1, C5, s=(41, 39)); add(pipe, P2, C6, s=(55, 39))
    add(conn, K, U, s=(13, 20), d=(11, 20)); add(conn, K, U, s=(13, 22), d=(11, 22))
    add(pipe, U, R, s=(8, 19), d=(8, 17))
    add(pipe, R, B, s=(8, 13), d=(8, 11))
    add(conn, B, m['C'], s=(7, 10))
    add(conn, m['S'], K, d=(16, 23))
    add(pipe, m['GR1'], m['CvR'], de=DOWN); add(pipe, m['GR2'], m['CvR'], de=LEFT)
    add(pipe, m['CvR'], R, se=UP, d=(10, 17))
    add(pipe, m['T'], V); add(pipe, m['A'], m['T']); add(pipe, m['L2'], m['T'], de=DOWN)
    add(conn, O1, K, s=(17, 11), d=(16, 19))
    add(conn, O2, H1, s=(25, 11), d=(25, 15)); add(conn, O3, H1, s=(29, 11), d=(29, 15))
    add(conn, O4, H2, s=(42, 11), d=(42, 15)); add(conn, O5, H2, s=(45, 11), d=(45, 15))
    add(conn, H1, m['HC'], s=(29, 19), de=RIGHT); add(conn, H2, m['HC'], s=(42, 19), de=LEFT)
    add(conn, m['HC'], m['WD'], se=UP)
    if LD is not None and m['WD'] is not None:
        add(conn, m['WD'], LD)
    add(conn, F1, E1, s=(2, 38), d=(3, 29)); add(conn, F2, E1, s=(10, 38), d=(5, 29))
    add(conn, F3, E2, s=(18, 38), d=(12, 30)); add(conn, F4, E2, s=(26, 38), d=(14, 30))
    add(conn, F5, m['S'], s=(34, 38)); add(conn, F6, m['S'], s=(48, 38))
    add(conn, m['C'], m['WD'])
    add(pipe, E1, U, s=(6, 26), d=(8, 23)); add(pipe, E2, U, s=(15, 27), d=(10, 23))
    add(pipe, P1, H1, s=(41, 37)); add(pipe, P2, H2, s=(55, 37))
    for w, sp, fa, fb in (('W1', 'S1', F1, F2), ('W2', 'S2', F3, F4), ('W3', 'S3', F5, F6)):
        add(pipe, m[w], m[sp], de=DOWN)
        add(pipe, m[sp], fb, se=UP, d=(fb.origin[0], 39)); add(pipe, m[sp], fa, se=RIGHT, d=(fa.origin[0], 39))
    add(pipe, m['W4'], O2, d=(25, 9)); add(pipe, m['W7'], O3, d=(33, 9))
    add(pipe, m['W5'], m['S5'], de=DOWN); add(pipe, m['S5'], O4, d=(42, 9)); add(pipe, m['S5'], O5, d=(49, 9))
    add(pipe, m['W6'], O1, d=(17, 9))
    add(pipe, m['L1'], m['SL'], de=DOWN); add(pipe, m['SL'], P1, se=LEFT, d=(37, 37)); add(pipe, m['SL'], P2, se=RIGHT, d=(51, 37))
    add(pipe, m['GI1'], m['CvI'], de=RIGHT); add(pipe, m['GI2'], m['CvI'], de=DOWN)
    add(pipe, m['CvI'], m['S'], se=UP)
    add(pipe, m['GA'], m['SA'], de=DOWN)
    add(pipe, m['SA'], B, se=UP, d=(11, 9)); add(pipe, m['SA'], E1, se=LEFT, d=(4, 29)); add(pipe, m['SA'], E2, se=RIGHT, d=(13, 30))
    order = list(range(len(nets)))
    if first_nets:
        order = [i for i in first_nets if i < len(nets)] + [i for i in order if i not in first_nets]
    failed = []
    for i in order:
        fn, args, kw = nets[i]
        before = len(L.failures)
        fn(*args, **kw)
        if len(L.failures) > before:
            failed.append(i)
    L.failed_nets = failed
    if not bad:
        try:
            L.place_diffusers()
        except P.PlacementError as e:
            L.failures.append(str(e))
        L.finish()
    return L, bad


def score(mv):
    first = []
    best = None
    for _ in range(4):
        L, bad = build(mv, first_nets=first)
        if best is None or len(L.failures) < len(best[0].failures):
            best = (L, bad)
        if not L.failures or bad:
            break
        first = L.failed_nets + [i for i in first if i not in L.failed_nets]
    L, bad = best
    length = sum(len(b['cells']) for b in L.belts)
    return len(bad) * 3 + len(L.failures), length, L


def search(iters=4000, seed=1, start=None):
    rng = random.Random(seed)
    cur = {k: list(v) for k, v in (start or MOVABLE).items()}
    best_f, best_len, _ = score(cur)
    print('start', best_f, best_len, flush=True)
    names = list(cur)
    for it in range(iters):
        cand = {k: list(v) for k, v in cur.items()}
        for _ in range(rng.choice([1, 1, 1, 2, 3])):
            n = rng.choice(names)
            r = rng.random()
            if r < 0.7:
                cand[n][1] += rng.randint(-3, 3); cand[n][2] += rng.randint(-3, 3)
            elif r < 0.9:
                cand[n][3] = rng.randrange(4)
            else:
                cand[n][1] = rng.randrange(0, 58); cand[n][2] = rng.randrange(4, 44)
        f, ln, _ = score(cand)
        if (f, ln) < (best_f, best_len) or (f == best_f and ln <= best_len + 5 and rng.random() < 0.05):
            cur, best_f, best_len = cand, f, ln
            if it % 50 == 0 or f < 3:
                print(it, best_f, best_len, flush=True)
        if best_f == 0 and it > 1500:
            break
    return cur, best_f, best_len


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == 'search':
        start = json.load(open(sys.argv[4])) if len(sys.argv) > 4 else None
        cur, f, ln = search(int(sys.argv[2]) if len(sys.argv) > 2 else 4000, int(sys.argv[3]) if len(sys.argv) > 3 else 1, start)
        print('final', f, ln)
        print(json.dumps(cur))
    else:
        L, bad = build()
        print(L.ascii())
        print('bad', bad)
        print('\n'.join(L.failures) or 'all routed')
