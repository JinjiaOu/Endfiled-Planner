"""预设产线生成工具库：复刻 App 里的建筑几何、放置规则、连线规则和 FlowSimulator，
让预设布局在 Python 里就能校验（摆放合法、口全部接对、模拟结果符合预期），再导出成存档 JSON。

对应的 Swift 实现：
- 端口几何：BuildingParser.parsePort / BuildingPort.resolvedPosition
- 放置规则：FactoryGridModel.canPlace
- 连线规则 + 流量模拟：FlowSimulator.Engine
改了 Swift 里这些逻辑的话，这里也要同步。
"""
import heapq
import json
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OTHER = ROOT / 'EndfiledPlanner' / 'other'

GRID_COLS, GRID_ROWS = 80, 80
UP, RIGHT, DOWN, LEFT = 0, 1, 2, 3
OFFSET = {UP: (0, -1), RIGHT: (1, 0), DOWN: (0, 1), LEFT: (-1, 0)}
DIR_NAME = {UP: '上', RIGHT: '右', DOWN: '下', LEFT: '左'}

BELT_CAP = 0.5
PIPE_CAP = 2.0
ACTIVATOR_NEED = 0.1
CLEANER_RATE = 0.5
VAPORIZER_RANGE = 5
CLEANER_ACCEPTED = {'污水', '壤晶废液', '惰性壤晶废液'}
VAPORIZER_GASES = {'惰气': '稳定', '水蒸气': '潮湿', '酸气': '酸性', '息壤气': '息壤'}
TRANSMUTER_ACTIVATORS = {'transmuter_1': '液化息壤', 'transmuter_2': '息壤气'}

WAREHOUSE_OUTLET = 'unloader_1'
WAREHOUSE_INLET = 'loader_1'
WAREHOUSE_SOURCE = 'log_hongs_bus_source'
WAREHOUSE_SEGMENT = 'log_hongs_bus'
PROTOCOL_CORE = 'sp_hub_1'
BRIDGES = {'item': 'log_connector', 'pipe': 'log_pipe_connector'}
MULTI_RECIPE = {'mix_pool_1', 'mix_pool_2'}
CATEGORY_KIND = {'基础生产': 'production', '合成制造': 'synthesis', '资源开采': 'extraction',
                 '物流': 'logistics', '仓储存取': 'storage', '电力': 'power', '核心': 'hub'}


def opposite(d):
    return (d + 2) % 4


def add(p, d, n=1):
    return (p[0] + OFFSET[d][0] * n, p[1] + OFFSET[d][1] * n)


# MARK: - 数据

def _load():
    devices = json.loads((OTHER / 'devices.json').read_text())['devices']
    recipes = json.loads((OTHER / 'recipes.json').read_text())['recipes']
    items = json.loads((OTHER / 'items.json').read_text())
    return devices, recipes, items


DEVICES_RAW, RECIPES_RAW, ITEMS_RAW = _load()
FUELS = {f['name']: f for f in json.loads((OTHER / 'fuels.json').read_text())['fuels']}
POWER_STATION = 'power_station_1'
DIFFUSER = 'power_diffuser_1'
ITEM_BY_NAME = {i['name']: i for i in ITEMS_RAW}
ITEM_BY_ID = {i['itemId']: i for i in ITEMS_RAW}
RECIPE_BY_ID = {r['id']: r for r in RECIPES_RAW}


def is_solid(name):
    return ITEM_BY_NAME.get(name, {'phase': 'solid'})['phase'] == 'solid'


def _deg_to_dir(y):
    return {0: DOWN, 90: RIGHT, 180: UP, 270: LEFT}[y % 360]


class Port:
    def __init__(self, index, kind, io, edge, idx):
        self.index, self.kind, self.io, self.edge, self.idx = index, kind, io, edge, idx


class Device:
    def __init__(self, raw):
        self.id = raw['id']
        self.name = raw['name']
        self.category = CATEGORY_KIND.get(raw['categoryName'])
        self.w, self.h = raw['size']['width'], raw['size']['depth']
        self.power = raw.get('powerConsume') or 0
        self.power_gen = raw.get('powerGenerate') or 0
        self.power_range = raw.get('powerRange')
        self.ports = []
        for i, p in enumerate(raw.get('ports') or []):
            flow = _deg_to_dir(p['rotation']['y'])
            direct = p['direction'] == 'output' or self.id == WAREHOUSE_INLET
            edge = flow if direct else opposite(flow)
            idx = p['position']['x'] if edge in (UP, DOWN) else p['position']['z']
            self.ports.append(Port(i, p['kind'], p['direction'], edge, idx))


DEVICES = {d['id']: Device(d) for d in DEVICES_RAW
           if CATEGORY_KIND.get(d['categoryName']) and d['size']['width'] > 0 and d['size']['depth'] > 0}
MAP_ONLY = {WAREHOUSE_SOURCE: 'wuling', WAREHOUSE_SEGMENT: 'wuling'}


def recipes_for(device_id):
    return [r for r in RECIPES_RAW if r['machineId'] == device_id]


# MARK: - 几何

def rotate_point(p, w, h, rot):
    c, r = p
    if rot == UP:
        return (c, r)
    if rot == RIGHT:
        return (h - 1 - r, c)
    if rot == DOWN:
        return (w - 1 - c, h - 1 - r)
    return (r, w - 1 - c)


class Building:
    def __init__(self, device, origin, rot):
        self.device, self.origin, self.rot = device, origin, rot
        self.recipe_id = None
        self.recipe_ids = []
        self.material_id = None
        self.port_assignments = {}
        self.flow_limit = None
        self.filter_id = None  # 准入口只放行的物品 itemId，同 App 的 filterItemID
        self.label = device.name

    @property
    def size(self):
        d = self.device
        return (d.w, d.h) if self.rot in (UP, DOWN) else (d.h, d.w)

    def cells(self):
        w, h = self.size
        return [(self.origin[0] + c, self.origin[1] + r) for r in range(h) for c in range(w)]

    def port_pos(self, port):
        d = self.device
        local = {UP: (port.idx, 0), DOWN: (port.idx, d.h - 1),
                 LEFT: (0, port.idx), RIGHT: (d.w - 1, port.idx)}[port.edge]
        rl = rotate_point(local, d.w, d.h, self.rot)
        cell = (self.origin[0] + rl[0], self.origin[1] + rl[1])
        facing = (port.edge + self.rot) % 4
        return cell, facing

    def port_external(self, port):
        cell, facing = self.port_pos(port)
        return add(cell, facing)

    def bounds(self):
        cs = self.cells()
        return (min(c for c, _ in cs), max(c for c, _ in cs), min(r for _, r in cs), max(r for _, r in cs))


# MARK: - 布局 + 放置规则

class PlacementError(Exception):
    pass


class Layout:
    def __init__(self, name, map_type):
        self.name = name
        self.map_type = map_type   # 'valley4' | 'wuling'
        self.buildings = []
        self.belts = []            # {'kind', 'cells', 'dirs', 'from', 'to'}
        self.bridges = {}          # cell -> kind
        self.reserved = set()      # 端口外部格：布线时不能占用（除了自己的起止点）
        self.soft = False          # True 时布线失败只记录不抛错，方便一次看到所有问题
        self.failures = []

    # 放置
    def occupied(self):
        occ = {}
        for b in self.buildings:
            for c in b.cells():
                occ[c] = b
        return occ

    def can_place(self, device, origin, rot):
        if MAP_ONLY.get(device.id, self.map_type) != self.map_type:
            return 'map'
        if device.id == PROTOCOL_CORE and any(b.device.id == PROTOCOL_CORE for b in self.buildings):
            return 'core'
        dummy = Building(device, origin, rot)
        w, h = dummy.size
        if origin[0] < 0 or origin[1] < 0 or origin[0] + w > GRID_COLS or origin[1] + h > GRID_ROWS:
            return 'bounds'
        occ = self.occupied()
        for c in dummy.cells():
            if c in occ:
                return f'overlap {occ[c].label}@{occ[c].origin}'
        if device.id == WAREHOUSE_SEGMENT:
            sources = [b for b in self.buildings if b.device.id == WAREHOUSE_SOURCE]
            if not any(abs(c[0] - s[0]) + abs(c[1] - s[1]) <= 6 for b in sources for s in b.cells() for c in dummy.cells()):
                return 'segment not near source'
        if device.id in (WAREHOUSE_OUTLET, WAREHOUSE_INLET):
            cell, facing = dummy.port_pos(device.ports[0])
            if self.map_type == 'valley4':
                if not ((facing == DOWN and cell[1] == 0) or (facing == RIGHT and cell[0] == 0)):
                    return 'valley4 edge'
            else:
                back = add(cell, opposite(facing))
                targets = [b for b in self.buildings if b.device.id in (WAREHOUSE_SOURCE, WAREHOUSE_SEGMENT)]
                if not any(back in t.cells() for t in targets):
                    return 'wuling dock'
        return None

    def place(self, device_id, col, row, rot=UP, recipe=None, recipes=None, material=None, label=None):
        device = DEVICES[device_id]
        err = self.can_place(device, (col, row), rot)
        if err:
            raise PlacementError(f'{self.name}: {device.name} @({col},{row}) rot={rot}: {err}')
        b = Building(device, (col, row), rot)
        if recipe:
            assert RECIPE_BY_ID[recipe]['machineId'] == device_id, (recipe, device_id)
            b.recipe_id = recipe
        if recipes:
            for r in recipes:
                assert RECIPE_BY_ID[r]['machineId'] == device_id, (r, device_id)
            b.recipe_ids = list(recipes)
        if material:
            b.material_id = ITEM_BY_NAME[material]['itemId']
        b.label = label or device.name
        self.buildings.append(b)
        for p in device.ports:
            if self._port_may_be_used(b, p):
                self.reserved.add(b.port_external(p))
        return b

    @staticmethod
    def _port_may_be_used(b, p):
        """有配方的机器：只有配方真会用到的物品/管道口才预留外部格，用不到的口前面允许走线
        （游戏里传送带也能贴着没用的口经过）；激活口、物流/仓储类建筑的口一律预留"""
        recipe_ids = ([b.recipe_id] if b.recipe_id else []) + list(b.recipe_ids)
        if not recipe_ids or b.device.category not in ('production', 'synthesis', 'extraction'):
            return True
        if b.device.id in TRANSMUTER_ACTIVATORS and p.kind == 'pipe' and p.io == 'input' and p.edge == DOWN:
            return True
        items = []
        for rid in recipe_ids:
            r = RECIPE_BY_ID[rid]
            items += [i['name'] for i in (r['ingredients'] if p.io == 'input' else r['outcomes'])]
        want = 'item' if p.kind == 'item' else 'pipe'
        return any(('item' if is_solid(n) else 'pipe') == want for n in items)

    def dock(self, device_id, target, side, offset, material=None, label=None):
        """武陵：把取货口/存货口贴在源桩/基段的某一边。side 是口朝哪边开，offset 是沿边从起点数第几格放 3 格长条的起点"""
        x0, x1, y0, y1 = target.bounds()
        rot = {UP: UP, RIGHT: RIGHT, DOWN: DOWN, LEFT: LEFT}[side]
        if side == UP:
            origin = (x0 + offset, y0 - 1)
        elif side == DOWN:
            origin = (x0 + offset, y1 + 1)
        elif side == LEFT:
            origin = (x0 - 1, y0 + offset)
        else:
            origin = (x1 + 1, y0 + offset)
        return self.place(device_id, origin[0], origin[1], rot, material=material, label=label)

    # 端口查询
    def ports(self, b, kind, io, edge=None):
        """按建筑未旋转时的边 + 边上偏移排好序的端口列表"""
        ps = [p for p in b.device.ports if p.kind == kind and p.io == io and (edge is None or p.edge == edge)]
        return ps

    def port(self, b, kind, io, n=0, edge=None):
        ps = self.ports(b, kind, io, edge)
        return ps[n]

    def pp(self, b, kind, io, edge, idx):
        """按未旋转时的边 + 边上偏移取端口（偏移就是 devices.json 里的 position.x / position.z）"""
        for p in b.device.ports:
            if p.kind == kind and p.io == io and p.edge == edge and p.idx == idx:
                return p
        raise KeyError((b.label, kind, io, edge, idx))

    def used_ports(self):
        used = set()
        for belt in self.belts:
            used.add((id(belt['from'][0]), belt['from'][1].index))
            used.add((id(belt['to'][0]), belt['to'][1].index))
        return used

    def best_pair(self, src, dst, kind, s_cell=None, d_cell=None, s_edge=None, d_edge=None):
        """没指定端口时，挑一对还没被占用、外部格距离最近的输出口/输入口"""
        used = self.used_ports()
        def cands(b, io, cell, edge):
            out = []
            for p in b.device.ports:
                if p.kind != kind or p.io != io or (id(b), p.index) in used:
                    continue
                if edge is not None and p.edge != edge:
                    continue
                if cell is not None and b.port_pos(p)[0] != cell:
                    continue
                out.append(p)
            return out
        best = None
        for sp in cands(src, 'output', s_cell, s_edge):
            se = src.port_external(sp)
            for dp in cands(dst, 'input', d_cell, d_edge):
                de = dst.port_external(dp)
                dist = abs(se[0] - de[0]) + abs(se[1] - de[1])
                if best is None or dist < best[0]:
                    best = (dist, sp, dp)
        if best is None:
            raise KeyError((src.label, dst.label, kind))
        return best[1], best[2]

    def port_at(self, b, kind, io, cell):
        for p in b.device.ports:
            if p.kind == kind and p.io == io and b.port_pos(p)[0] == cell:
                return p
        raise KeyError((b.label, kind, io, cell))

    # MARK: 布线
    def connect(self, src, src_port, dst, dst_port, via=None, label=None):
        kind = src_port.kind
        assert kind == dst_port.kind and src_port.io == 'output' and dst_port.io == 'input'
        head = src.port_external(src_port)
        _, head_facing = src.port_pos(src_port)
        tail = dst.port_external(dst_port)
        _, tail_facing = dst.port_pos(dst_port)
        final_dir = opposite(tail_facing)
        path = self._route(kind, head, head_facing, tail, final_dir, via or [])
        if path is None and getattr(self, 'soft', False):
            self.failures.append(f'{src.label}{src.origin} -> {dst.label}{dst.origin} ({kind})')
            return None
        if path is None:
            raise PlacementError(f'{self.name}: 布线失败 {src.label}{src.origin} -> {dst.label}{dst.origin} ({kind})')
        dirs = []
        for i, c in enumerate(path):
            if i < len(path) - 1:
                n = path[i + 1]
                dirs.append({(0, -1): UP, (1, 0): RIGHT, (0, 1): DOWN, (-1, 0): LEFT}[(n[0] - c[0], n[1] - c[1])])
            else:
                dirs.append(final_dir)
        belt = {'kind': kind, 'cells': path, 'dirs': dirs, 'from': (src, src_port), 'to': (dst, dst_port),
                'label': label or f'{src.label}->{dst.label}'}
        # 交叉点补桥
        for c, d in zip(path, dirs):
            for other in self.belts:
                if other['kind'] != kind:
                    continue
                for oc, od in zip(other['cells'], other['dirs']):
                    if oc == c:
                        self.bridges[c] = kind
        self.belts.append(belt)
        return belt

    def _line_map(self):
        m = {}
        for belt in self.belts:
            cells = belt['cells']
            for i, (c, d) in enumerate(zip(cells, belt['dirs'])):
                straight = 0 < i < len(cells) - 1 and belt['dirs'][i - 1] == d
                m.setdefault(c, []).append((belt['kind'], d % 2, straight))
        return m

    def _route(self, kind, head, head_facing, tail, final_dir, via):
        occ = self.occupied()
        lines = self._line_map()
        for c in (head, tail):
            if not (0 <= c[0] < GRID_COLS and 0 <= c[1] < GRID_ROWS) or c in occ or c in lines:
                return None
        if head == tail:
            return [head] if head_facing == final_dir and not via else None
        waypoints = [head] + list(via) + [tail]
        full = [head]
        for wi in range(len(waypoints) - 1):
            a, z = waypoints[wi], waypoints[wi + 1]
            seg = self._astar(kind, a, z, head_facing if wi == 0 else None, occ, lines, set(full[:-1]), head, tail,
                              forbid_last=opposite(final_dir) if wi == len(waypoints) - 2 else None)
            if seg is None:
                return None
            full += seg[1:]
        return full

    def _astar(self, kind, start, goal, first_dir, occ, lines, used, head, tail, forbid_last=None):
        """在格子上找 start→goal 的线。规则：
        - 不能穿建筑、不能占别的口的外部格（留给它们自己接线）
        - 已有线的格子只能垂直直穿（双方都是直线段），同类型的交叉之后补物流桥/管道桥，传送带和管道互相不补
        - 起点、终点都可以从侧面拐，只是不能倒着走回口里
        代价：步数 + 转弯 + 交叉惩罚"""
        def enter_cost(c, d):
            if not (0 <= c[0] < GRID_COLS and 0 <= c[1] < GRID_ROWS) or c in occ or c in used:
                return None
            if c in self.reserved and c not in (head, tail):
                return None
            cost = 1
            for k, axis, straight in lines.get(c, []):
                if not straight or axis == d % 2 or c in (head, tail):
                    return None
                cost += 12 if k == kind else 6
            return cost

        frontier = [(0, 0, start, None)]
        best = {(start, None): 0}
        parent = {}
        while frontier:
            f, g, cell, d_in = heapq.heappop(frontier)
            if cell == goal:
                path = [cell]
                key = (cell, d_in)
                while key in parent:
                    key = parent[key]
                    path.append(key[0])
                return path[::-1]
            if g > best.get((cell, d_in), 1e9):
                continue
            for d in (UP, RIGHT, DOWN, LEFT):
                if cell == start and first_dir is not None and d == opposite(first_dir):
                    continue
                if d_in is not None and d == opposite(d_in):
                    continue
                n = add(cell, d)
                if n == goal and forbid_last is not None and d == forbid_last:
                    continue
                step = enter_cost(n, d)
                if step is None:
                    continue
                # 有线的格子只能直穿，不能在交叉点拐弯
                if d_in is not None and d != d_in:
                    if cell in lines:
                        continue
                    step += 3
                ng = g + step
                key = (n, d)
                if ng < best.get(key, 1e9):
                    best[key] = ng
                    parent[key] = (cell, d_in)
                    h = abs(n[0] - goal[0]) + abs(n[1] - goal[1])
                    heapq.heappush(frontier, (ng + h, ng, n, d))
        return None

    def finish(self):
        """把交叉点的桥作为建筑追加到最后（App 里自动补桥也是追加在末尾，连线匹配时机器端口优先）"""
        for cell, kind in sorted(self.bridges.items()):
            dev = DEVICES[BRIDGES[kind]]
            b = Building(dev, cell, UP)
            b.label = dev.name
            occ = self.occupied()
            assert cell not in occ, f'桥的位置被建筑占了 {cell}'
            self.buildings.append(b)

    def place_diffusers(self, region=None):
        """贪心摆供电桩：每次挑一个能覆盖最多"耗电 > 0 且还没通电"建筑的空位（不压建筑、不压线），
        直到全部通电。region=(x0, x1, y0, y1) 限定候选范围。返回放了几个"""
        dev = DEVICES[DIFFUSER]
        line_cells = {c for belt in self.belts for c in belt['cells']}
        placed = 0
        while True:
            need = [b for b in self.buildings if b.device.power > 0 and not covered(self, b)]
            if not need:
                return placed
            occ = self.occupied()
            best = None
            x0, x1, y0, y1 = region or (0, GRID_COLS - 2, 0, GRID_ROWS - 2)
            for y in range(y0, y1 + 1):
                for x in range(x0, x1 + 1):
                    cells = [(x, y), (x + 1, y), (x, y + 1), (x + 1, y + 1)]
                    if any(c in occ or c in line_cells for c in cells):
                        continue
                    if not all(0 <= c[0] < GRID_COLS and 0 <= c[1] < GRID_ROWS for c in cells):
                        continue
                    bd = (x, x + 1, y, y + 1)
                    n = sum(1 for b in need if _overlap(bd, dev.power_range, b.bounds()))
                    if n and (best is None or n > best[0]):
                        best = (n, x, y)
            if best is None:
                raise PlacementError(f'{self.name}: 供电桩放不下，还有 {len(need)} 个建筑没通电: {[b.label for b in need][:5]}')
            self.place(DIFFUSER, best[1], best[2], UP, label='供电桩')
            placed += 1

    # MARK: 导出
    def to_json(self):
        ns = uuid.uuid5(uuid.NAMESPACE_URL, f'endfield-planner/preset/{self.name}')
        out_buildings = []
        for i, b in enumerate(self.buildings):
            d = {'id': str(uuid.uuid5(ns, f'b{i}')).upper(), 'definitionID': b.device.id,
                 'origin': {'col': b.origin[0], 'row': b.origin[1]}, 'rotation': b.rot, 'isActive': True,
                 'selectedRecipeIDs': sorted(b.recipe_ids),
                 'outputPortAssignments': {str(k): v for k, v in sorted(b.port_assignments.items())}}
            if b.recipe_id:
                d['selectedRecipeID'] = b.recipe_id
            if b.material_id:
                d['outletMaterialID'] = b.material_id
            if b.flow_limit is not None:
                d['flowLimitPerMin'] = b.flow_limit
            if b.filter_id:
                d['filterItemID'] = b.filter_id
            out_buildings.append(d)
        out_belts = []
        for i, belt in enumerate(self.belts):
            segs = []
            for j, (c, d) in enumerate(zip(belt['cells'], belt['dirs'])):
                off = {'col': OFFSET[d][0], 'row': OFFSET[d][1]}
                segs.append({'id': str(uuid.uuid5(ns, f'l{i}s{j}')).upper(), 'cell': {'col': c[0], 'row': c[1]},
                             'axis': 'vertical' if d in (UP, DOWN) else 'horizontal',
                             'fromDir': off, 'toDir': off,
                             'lineType': 'belt' if belt['kind'] == 'item' else 'pipe'})
            out_belts.append({'id': str(uuid.uuid5(ns, f'l{i}')).upper(), 'segments': segs})
        return {'buildings': out_buildings, 'beltNetwork': {'belts': out_belts}, 'savedAt': 0,
                'mapType': '四号谷地' if self.map_type == 'valley4' else '武陵', 'dataVersion': 2}

    def ascii(self):
        grid = [['.'] * GRID_COLS for _ in range(GRID_ROWS)]
        for belt in self.belts:
            ch = {UP: '^', DOWN: 'v', LEFT: '<', RIGHT: '>'} if belt['kind'] == 'item' else {UP: '|', DOWN: '|', LEFT: '-', RIGHT: '-'}
            for c, d in zip(belt['cells'], belt['dirs']):
                grid[c[1]][c[0]] = ch[d]
        for k, b in enumerate(self.buildings):
            mark = '#' if b.device.id in BRIDGES.values() else chr(ord('A') + k % 26)
            for c in b.cells():
                grid[c[1]][c[0]] = mark
        return '\n'.join(f'{r:2d} ' + ''.join(row) for r, row in enumerate(grid))


# MARK: - 流量模拟（FlowSimulator.Engine 的逐行复刻）

class _Link:
    def __init__(self, kind):
        self.kind = kind
        self.capacity = BELT_CAP if kind == 'item' else PIPE_CAP
        self.from_node, self.to_node = -1, -1
        self.offer, self.flow, self.pass_flow = {}, {}, {}
        self.cap_scale = 1.0

    def pass_offer(self, item):
        return self.cap_scale * self.pass_flow.get(item, 0)


class _PortInfo:
    def __init__(self, port, cell, facing):
        self.port, self.cell, self.facing = port, cell, facing
        self.link = None

    @property
    def external(self):
        return add(self.cell, self.facing)

    @property
    def is_input(self):
        return self.port.io == 'input'

    @property
    def is_output(self):
        return self.port.io == 'output'


class _Node:
    def __init__(self, b, kind):
        self.b, self.kind = b, kind
        self.ports = [_PortInfo(p, *b.port_pos(p)) for p in b.device.ports]
        self.bounds = b.bounds()
        self.has_recipe = False
        self.ingredients, self.products = [], []
        self.required_env = None
        self.activator_port, self.activator_item = None, None
        self.conditioner_limit = float('inf')
        self.conditioner_filter = None
        self.throttle, self.t_in, self.r_min = 1.0, 1.0, 1.0
        self.limiting, self.gate_note = None, None
        self.conditioner_scale = 1.0
        self.splitter_caps = {}  # 出口线 → 物品 → 这一路最多收多少；只往下调，同 App
        self.active_env = None
        self.consumed = {}
        self.unpowered = False
        self.generated = 0.0
        self.fuel = None


ROUTER_KINDS = {'splitter', 'converger', 'bridge', 'conditioner'}


def _node_kind(dev):
    special = {WAREHOUSE_OUTLET: 'unloader', WAREHOUSE_INLET: 'loader', 'liquid_cleaner_1': 'cleaner',
               'log_splitter': 'splitter', 'log_pipe_splitter': 'splitter',
               'log_converger': 'converger', 'log_pipe_converger': 'converger',
               'log_connector': 'bridge', 'log_pipe_connector': 'bridge',
               'log_conditioner': 'conditioner', 'log_pipe_conditioner': 'conditioner',
               'vaporizer_1': 'vaporizer', POWER_STATION: 'generator'}
    if dev.id in special:
        return special[dev.id]
    return 'machine' if dev.category in ('production', 'synthesis', 'extraction') else 'ignored'


def net_flows(recipe_list):
    net = {}
    for r in recipe_list:
        s = max(round(r['seconds']), 1)
        for i in r['ingredients']:
            net[i['name']] = net.get(i['name'], 0) - i['count'] / s
        for o in r['outcomes']:
            net[o['name']] = net.get(o['name'], 0) + o['count'] / s
    return net


def _overlap(a, e, b):
    """b 的范围是否跟 a 向四周扩 e 格后的范围重叠（bounds = (x0, x1, y0, y1)）"""
    return a[1] >= b[0] - e and a[0] <= b[1] + e and a[3] >= b[2] - e and a[2] <= b[3] + e


def covered(layout, b):
    return any(_overlap(d.bounds(), d.device.power_range, b.bounds()) for d in layout.buildings if d.device.power_range)


def split_shares(total, caps):
    """同 App 的 splitShares：平均分，有上限的路分不满就给上限，剩下的再匀给其它路"""
    shares = [0.0] * len(caps)
    open_ = list(range(len(caps)))
    remaining = total
    while open_:
        share = remaining / len(open_)
        tight = [i for i in open_ if caps[i] is not None and caps[i] < share]
        if not tight:
            for i in open_:
                shares[i] = share
            break
        for i in tight:
            shares[i] = caps[i]
            remaining -= caps[i]
        open_ = [i for i in open_ if i not in tight]
    return shares


def simulate(layout, max_iter=400, eps=1e-7):
    nodes = []
    for b in layout.buildings:
        n = _Node(b, _node_kind(b.device))
        if n.kind == 'machine':
            if b.device.id in MULTI_RECIPE:
                sel = [r for r in recipes_for(b.device.id) if r['id'] in b.recipe_ids]
                if sel:
                    n.has_recipe = True
                    net = net_flows(sel)
                    n.ingredients = [(k, -v) for k, v in net.items() if v < -1e-9]
                    n.products = [(k, v) for k, v in net.items() if v > 1e-9]
            elif b.recipe_id:
                r = RECIPE_BY_ID[b.recipe_id]
                s = max(round(r['seconds']), 1)
                n.has_recipe = True
                n.ingredients = [(i['name'], i['count'] / s) for i in r['ingredients']]
                n.products = [(o['name'], o['count'] / s) for o in r['outcomes']]
                env = r.get('gasEnvName') or None
                n.required_env = env[:-2] if env and env.endswith('环境') else env
            if b.device.id in TRANSMUTER_ACTIVATORS:
                n.activator_item = TRANSMUTER_ACTIVATORS[b.device.id]
                for pi, p in enumerate(n.ports):
                    if p.is_input and p.port.kind == 'pipe' and p.port.edge == DOWN:
                        n.activator_port = pi
                        break
        elif n.kind == 'vaporizer':
            n.activator_port = next(pi for pi, p in enumerate(n.ports) if p.is_input and p.port.kind == 'pipe')
        elif n.kind == 'unloader':
            if b.material_id:
                n.products = [(ITEM_BY_ID[b.material_id]['name'], BELT_CAP)]
        elif n.kind == 'conditioner':
            cap = PIPE_CAP if b.device.id == 'log_pipe_conditioner' else BELT_CAP
            n.conditioner_limit = min(cap, max(b.flow_limit, 0) / 60) if b.flow_limit is not None else cap
            n.conditioner_filter = ITEM_BY_ID[b.filter_id]['name'] if b.filter_id else None
        nodes.append(n)

    diffusers = [(n.bounds, n.b.device.power_range) for n in nodes if n.b.device.power_range]
    for n in nodes:
        if n.b.device.power > 0:
            n.unpowered = not any(_overlap(bd, r, n.bounds) for bd, r in diffusers)

    links = []
    out_ext, in_ext, in_cell = {}, {}, {}
    for ni, n in enumerate(nodes):
        for pi, p in enumerate(n.ports):
            key = (p.external, p.port.kind)
            if p.is_output:
                out_ext.setdefault(key, (ni, pi))
            else:
                in_ext.setdefault(key, (ni, pi))
                in_cell.setdefault((p.cell, p.port.kind), (ni, pi))

    def connect(kind, frm, to):
        link = _Link(kind)
        idx = len(links)
        link.from_node = frm[0]
        nodes[frm[0]].ports[frm[1]].link = idx
        if to is not None and nodes[to[0]].ports[to[1]].link is None:
            link.to_node = to[0]
            nodes[to[0]].ports[to[1]].link = idx
        links.append(link)
        return link

    belt_links = []
    for belt in layout.belts:
        head, tail = belt['cells'][0], belt['cells'][-1]
        frm = out_ext.get((head, belt['kind']))
        if frm is None or nodes[frm[0]].ports[frm[1]].link is not None:
            belt_links.append(None)
            continue
        belt_links.append(connect(belt['kind'], frm, in_ext.get((tail, belt['kind']))))
    for ni, n in enumerate(nodes):
        for pi, p in enumerate(n.ports):
            if not p.is_output or p.link is not None:
                continue
            target = in_cell.get((p.external, p.port.kind))
            if target is None or target[0] == ni:
                continue
            tp = nodes[target[0]].ports[target[1]]
            if tp.link is None and tp.external == p.cell:
                connect(p.port.kind, (ni, pi), target)

    producers, vaporizers, terminals = [], [], []
    for i, n in enumerate(nodes):
        if n.kind == 'machine':
            producers.append(i)
            terminals.append(i)
        elif n.kind == 'unloader':
            producers.append(i)
        elif n.kind == 'vaporizer':
            vaporizers.append(i)
        elif n.kind in ('loader', 'cleaner', 'generator', 'ignored'):
            terminals.append(i)
    routers = [i for i, n in enumerate(nodes) if n.kind in ROUTER_KINDS]
    indeg = {r: 0 for r in routers}
    for l in links:
        if l.from_node >= 0 and l.to_node >= 0 and nodes[l.from_node].kind in ROUTER_KINDS and nodes[l.to_node].kind in ROUTER_KINDS:
            indeg[l.to_node] += 1
    queue = [r for r in routers if indeg[r] == 0]
    order, visited = [], set()
    while queue:
        r = queue.pop(0)
        if r in visited:
            continue
        visited.add(r)
        order.append(r)
        for p in nodes[r].ports:
            if p.link is None:
                continue
            l = links[p.link]
            if l.from_node == r and l.to_node >= 0 and nodes[l.to_node].kind in ROUTER_KINDS:
                indeg[l.to_node] -= 1
                if indeg[l.to_node] == 0:
                    queue.append(l.to_node)
    order += [r for r in routers if r not in visited]

    def in_links(n):
        return [p.link for p in n.ports if p.is_input and p.link is not None]

    def out_links(n):
        return [p.link for p in n.ports if p.is_output and p.link is not None]

    def out_links_for(n, item):
        kind = 'item' if is_solid(item) else 'pipe'
        all_kind = [(pi, p) for pi, p in enumerate(n.ports) if p.is_output and p.port.kind == kind]
        assign = n.b.port_assignments
        if assign:
            mine = [p for pi, p in all_kind if assign.get(pi) == item]
            if mine:
                return [p.link for p in mine if p.link is not None]
            free = [p for pi, p in all_kind if pi not in assign]
            if free:
                return [p.link for p in free if p.link is not None]
        return [p.link for _, p in all_kind if p.link is not None]

    def finalize(li):
        l = links[li]
        total = sum(l.offer.values())
        l.cap_scale = l.capacity / total if total > l.capacity else 1
        l.flow = {k: v * l.cap_scale for k, v in l.offer.items()}

    def env_ok(n, env):
        x0, x1, y0, y1 = n.bounds
        for vi in vaporizers:
            v = nodes[vi]
            if v.active_env != env:
                continue
            a0, a1, b0, b1 = v.bounds
            e = VAPORIZER_RANGE
            if a1 >= x0 - e and a0 <= x1 + e and b1 >= y0 - e and b0 <= y1 + e:
                return True
        return False

    def eval_machine(n):
        arrivals, act = {}, {}
        for pi, p in enumerate(n.ports):
            if not p.is_input or p.link is None:
                continue
            target = act if pi == n.activator_port else arrivals
            for item, v in links[p.link].flow.items():
                target[item] = target.get(item, 0) + v
        t = 1.0
        n.limiting = None
        if not n.has_recipe:
            t = 0
        for name, rate in n.ingredients:
            if rate > 0:
                ratio = arrivals.get(name, 0) / rate
                if ratio < t:
                    t, n.limiting = ratio, name
        if n.required_env and not env_ok(n, n.required_env):
            t = 0
            n.gate_note = f'需要{n.required_env}环境'
        if n.unpowered:
            t = 0
            n.gate_note = '未通电'
        if n.activator_item:
            rate = act.get(n.activator_item, 0)
            ok = n.activator_port is not None and rate >= ACTIVATOR_NEED - 1e-9
            if not ok:
                t = 0
                n.gate_note = f'{n.activator_item}注入不足'
            if n.activator_port is not None and n.ports[n.activator_port].link is not None and ok:
                links[n.ports[n.activator_port].link].pass_flow[n.activator_item] = min(1, ACTIVATOR_NEED / rate)
        n.t_in = max(0, min(1, t))
        need = {}
        for name, rate in n.ingredients:
            need[name] = need.get(name, 0) + rate
        for pi, p in enumerate(n.ports):
            if not p.is_input or pi == n.activator_port or p.link is None:
                continue
            l = links[p.link]
            for item in list(l.flow.keys()):
                arrived = arrivals.get(item, 0)
                if item in need and arrived > 0:
                    l.pass_flow[item] = min(1, n.t_in * need[item] / arrived)
                else:
                    l.pass_flow[item] = 0

    cap_delta = [0.0]

    def step():
        for l in links:
            l.offer, l.flow, l.cap_scale, l.pass_flow = {}, {}, 1.0, {}
        for n in nodes:
            n.consumed, n.gate_note = {}, None
        cap_delta[0] = 0.0
        for i in producers:
            n = nodes[i]
            for name, rate in n.products:
                outs = out_links_for(n, name)
                if not outs:
                    continue
                for li in outs:
                    links[li].offer[name] = links[li].offer.get(name, 0) + rate * n.throttle / len(outs)
            for li in out_links(n):
                finalize(li)
        for i in order:
            n = nodes[i]
            ins, outs = in_links(n), out_links(n)
            if n.kind == 'splitter':
                if ins and outs:
                    finalize(ins[0])
                    for item, v in links[ins[0]].flow.items():
                        caps = [n.splitter_caps.get(o, {}).get(item) for o in outs]
                        for o, amount in zip(outs, split_shares(v, caps)):
                            links[o].offer[item] = links[o].offer.get(item, 0) + amount
            elif n.kind == 'converger':
                if outs:
                    for il in ins:
                        finalize(il)
                        for item, v in links[il].flow.items():
                            links[outs[0]].offer[item] = links[outs[0]].offer.get(item, 0) + v
            elif n.kind == 'bridge':
                for p in n.ports:
                    if not p.is_input or p.link is None:
                        continue
                    op = next((q for q in n.ports if q.is_output and q.facing == opposite(p.facing)), None)
                    if op is None or op.link is None:
                        continue
                    finalize(p.link)
                    for item, v in links[p.link].flow.items():
                        links[op.link].offer[item] = links[op.link].offer.get(item, 0) + v
            elif n.kind == 'conditioner':
                if ins and outs:
                    finalize(ins[0])
                    allowed = {k: v for k, v in links[ins[0]].flow.items()
                               if n.conditioner_filter is None or k == n.conditioner_filter}
                    total = sum(allowed.values())
                    scale = n.conditioner_limit / total if total > n.conditioner_limit else 1
                    n.conditioner_scale = scale
                    for item, v in allowed.items():
                        links[outs[0]].offer[item] = links[outs[0]].offer.get(item, 0) + v * scale
            for o in outs:
                finalize(o)
        for li in range(len(links)):
            finalize(li)
        for i in vaporizers:
            n = nodes[i]
            n.active_env = None
            if n.activator_port is None or n.ports[n.activator_port].link is None:
                continue
            flow = links[n.ports[n.activator_port].link].flow
            best = None
            for gas in VAPORIZER_GASES:
                rate = flow.get(gas, 0)
                if rate >= ACTIVATOR_NEED - 1e-9 and rate > (best[1] if best else 0):
                    best = (gas, rate)
            if best:
                n.active_env = VAPORIZER_GASES[best[0]]
                links[n.ports[n.activator_port].link].pass_flow[best[0]] = min(1, ACTIVATOR_NEED / best[1])
            else:
                n.gate_note = '气体不足'
        for i in terminals:
            n = nodes[i]
            if n.kind == 'machine':
                eval_machine(n)
            elif n.kind == 'loader':
                for li in in_links(n):
                    for item, v in links[li].flow.items():
                        links[li].pass_flow[item] = 1
                        n.consumed[item] = n.consumed.get(item, 0) + v
            elif n.kind == 'generator':
                arr = {}
                for li in in_links(n):
                    for item, v in links[li].flow.items():
                        arr[item] = arr.get(item, 0) + v
                cands = [(FUELS[k], v) for k, v in arr.items() if v > 1e-9 and k in FUELS]
                best = max(cands, key=lambda x: x[0]['powerProvide']) if cands else None
                n.fuel, n.generated = None, 0.0
                if best:
                    need = 1 / best[0]['secondsPerItem']
                    n.fuel = best[0]['name']
                    n.generated = best[0]['powerProvide'] * min(1, best[1] / need)
                for li in in_links(n):
                    for item in links[li].flow:
                        links[li].pass_flow[item] = min(1, (1 / best[0]['secondsPerItem']) / best[1]) if best and item == best[0]['name'] else 0
            elif n.kind == 'cleaner' and n.unpowered:
                pass
            elif n.kind == 'cleaner':
                for li in in_links(n):
                    acc = sum(v for k, v in links[li].flow.items() if k in CLEANER_ACCEPTED)
                    frac = min(1, CLEANER_RATE / acc) if acc > 0 else 1
                    for item, v in links[li].flow.items():
                        if item in CLEANER_ACCEPTED:
                            links[li].pass_flow[item] = frac
                            n.consumed[item] = n.consumed.get(item, 0) + v * frac
        for i in reversed(order):
            n = nodes[i]
            ins, outs = in_links(n), out_links(n)
            if n.kind == 'splitter':
                if ins and outs:
                    for item, v in links[ins[0]].flow.items():
                        accepted = 0.0
                        for o in outs:
                            sent = links[o].offer.get(item, 0)
                            pas = links[o].pass_offer(item)
                            accepted += sent * pas
                            if sent <= 1e-12 or pas >= 1 - 1e-6:
                                continue
                            old = n.splitter_caps.get(o, {}).get(item)
                            cap = min(old if old is not None else float('inf'), sent * pas)
                            n.splitter_caps.setdefault(o, {})[item] = cap
                            cap_delta[0] = max(cap_delta[0], (old if old is not None else sent) - cap)
                        links[ins[0]].pass_flow[item] = accepted / v if v > 1e-12 else max(links[o].pass_offer(item) for o in outs)
            elif n.kind == 'converger':
                if outs:
                    for il in ins:
                        for item in links[il].flow:
                            links[il].pass_flow[item] = links[outs[0]].pass_offer(item)
            elif n.kind == 'bridge':
                for p in n.ports:
                    if not p.is_input or p.link is None:
                        continue
                    op = next((q for q in n.ports if q.is_output and q.facing == opposite(p.facing)), None)
                    if op is None or op.link is None:
                        continue
                    for item in links[p.link].flow:
                        links[p.link].pass_flow[item] = links[op.link].pass_offer(item)
            elif n.kind == 'conditioner':
                if ins and outs:
                    for item in links[ins[0]].flow:
                        blocked = n.conditioner_filter is not None and item != n.conditioner_filter
                        links[ins[0]].pass_flow[item] = 0 if blocked else n.conditioner_scale * links[outs[0]].pass_offer(item)
        delta = 0
        for i in producers:
            n = nodes[i]
            r = 1.0
            for name, rate in n.products:
                if rate <= 0:
                    continue
                outs = out_links_for(n, name)
                rx = sum(links[o].pass_offer(name) for o in outs) / len(outs) if outs else 0
                r = min(r, rx)
            n.r_min = r
            new = max(0, min(n.throttle, n.t_in, n.throttle * r))
            delta = max(delta, abs(new - n.throttle))
            n.throttle = new
        return max(delta, cap_delta[0])

    converged = False
    for _ in range(max_iter):
        if step() < eps:
            converged = True
            break

    machines = []
    for n in nodes:
        if n.kind in ('machine', 'unloader'):
            status, detail = 'running', None
            if n.kind == 'unloader' and not n.products:
                status, detail = 'noRecipe', '未设置取货材料'
            elif n.kind == 'machine' and not n.has_recipe:
                status, detail = 'noRecipe', '未选择配方'
            elif n.throttle < 0.999:
                if n.gate_note:
                    status, detail = 'inactive', n.gate_note
                elif n.t_in < 0.999 and n.t_in <= n.throttle * n.r_min + 1e-6:
                    status, detail = 'starved', f'缺少 {n.limiting}'
                else:
                    status, detail = 'blocked', '下游吃不下'
            outputs = {name: rate * n.throttle * 60 for name, rate in n.products}
            machines.append({'b': n.b, 'status': status, 'throttle': n.throttle, 'detail': detail, 'outputs': outputs})
        elif n.kind == 'vaporizer':
            machines.append({'b': n.b, 'status': 'running' if n.active_env else 'inactive', 'throttle': 1 if n.active_env else 0,
                             'detail': n.active_env or n.gate_note, 'outputs': {}})
    sinks = [{'b': n.b, 'consumed': {k: v * 60 for k, v in n.consumed.items()}} for n in nodes if n.kind in ('loader', 'cleaner')]
    unpowered = [n.b.label for n in nodes if n.unpowered]
    generated = sum(n.generated for n in nodes if n.kind == 'generator') + sum(n.b.device.power_gen for n in nodes if n.b.device.id == PROTOCOL_CORE)
    consumed = sum(n.b.device.power for n in nodes if not n.unpowered)
    generators = [(n.b.label, n.fuel, round(n.generated, 1)) for n in nodes if n.kind == 'generator']

    # 每条线实际接到了哪里（用于核对布线意图）
    link_report = []
    for belt, link in zip(layout.belts, belt_links):
        ok = (link is not None and nodes[link.from_node].b is belt['from'][0]
              and link.to_node >= 0 and nodes[link.to_node].b is belt['to'][0])
        link_report.append((belt, ok, link))
    return {'machines': machines, 'sinks': sinks, 'converged': converged, 'links': link_report,
            'unpowered': unpowered, 'power': (consumed, generated), 'generators': generators}


def report(layout, sim, expect_partial=()):
    print(f'== {layout.name}')
    bad_links = [(b['label'], b['cells'][0], b['cells'][-1]) for b, ok, _ in sim['links'] if not ok]
    for item in bad_links:
        print('  BAD LINK', item)
    rows = []
    for m in sim['machines']:
        rows.append((m['b'].label, m['status'], round(m['throttle'] * 100), m['detail'],
                     {k: round(v, 2) for k, v in m['outputs'].items()}))
    not_full = [r for r in rows if r[1] != 'running' or r[2] < 100]
    for r in not_full:
        tag = 'ok-partial' if r[0] in expect_partial else 'NOT FULL'
        print(f'  {tag}: {r}')
    for s in sim['sinks']:
        print('  sink', s['b'].label, {k: round(v, 2) for k, v in s['consumed'].items()})
    power, gen = sim['power']
    print(f'  converged={sim["converged"]} machines={len(rows)} buildings={len(layout.buildings)} '
          f'belts={len(layout.belts)} bridges={len(layout.bridges)} 耗电={power}MW 发电={round(gen, 1)}MW {sim["generators"]}')
    problems = [r for r in not_full if r[0] not in expect_partial]
    if sim['unpowered']:
        print('  UNPOWERED', sim['unpowered'])
        problems.append(('unpowered', sim['unpowered']))
    if gen + 1e-6 < power:
        print('  POWER SHORTAGE', power - gen)
        problems.append(('shortage', power - gen))
    return bad_links, problems
