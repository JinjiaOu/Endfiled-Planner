"""把 MSC 基建攻略表里的新蓝图合并进 blueprints.json（参数：sections.json 原 blueprints.json 输出路径）"""
import json, sys, re
secs = json.load(open(sys.argv[1]))
app = json.load(open(sys.argv[2]))
orig_text = open(sys.argv[2], encoding='utf-8').read()

def sec(sheet, title):
    found = [s for s in secs if s['sheet'] == sheet and s['title'] == title]
    assert len(found) == 1, (sheet, title, len(found))
    return found[0]['items']

SKIP_HOWTO = ('参考视频', '详见右侧', '同上图')
def notes_of(it, extra=None):
    f = it['fields']; parts = []
    if it.get('serial'):
        parts.append('编号' + it['serial'].get('B', '') + it['serial'].get('C', ''))
    if it.get('label') and not re.fullmatch(r'\d+', it['label']):
        parts.append(it['label'])
    if f.get('product'): parts.append('产物：' + f['product'])
    if f.get('cost'): parts.append('消耗：' + f['cost'])
    if f.get('rate'): parts.append('效率：' + f['rate'])
    if f.get('daily'): parts.append('24h产量：' + f['daily'])
    if f.get('power'): parts.append(('' if re.match(r'(发电|耗电|震荡)', f['power']) else '耗电：') + f['power'])
    if f.get('area'): parts.append('占地：' + f['area'])
    if f.get('howto') and not f['howto'].startswith(SKIP_HOWTO): parts.append(f['howto'])
    if f.get('note'): parts.append(f['note'])
    if f.get('extra') and not f['extra'].startswith(SKIP_HOWTO): parts.append(f['extra'])
    if extra: parts.append(extra)
    return '，'.join(p.strip(' ，/') for p in parts if p.strip(' ，/'))

def items_to_bps(set_num, items, names=None, extra_notes=None, start=1):
    out = []
    for i, it in enumerate(items):
        order = start + i
        name = (names or {}).get(it['code']) or it['fields'].get('name') or '未命名'
        out.append({'id': f'bp_{set_num}_{order:02d}', 'order': order, 'name': name, 'code': it['code'],
                    'notes': notes_of(it, (extra_notes or {}).get(it['code']))})
    return out

sets = {s['id']: s for s in app['blueprintSets']}

# 1. 四号谷地过渡阶段：App 里原来的码是从截图识别的，多处认错（还有 J、Y 这种蓝图码里不会出现的字母），换成文档版本，分组不变
trans = {it['code']: it for it in sec('四号谷地', '过渡阶段')}
def pick(*codes): return [trans[c] for c in codes]
row11, row12 = 'EF0170i8o94I457O2Ai', 'EF013Eo7e21i1auu0579'
sets['set_030']['blueprints'] = items_to_bps('030', pick('EF016u02o3e4u71e8O83e'))
sets['set_031']['blueprints'] = items_to_bps('031', pick(row11, row12, 'EF01U9e3865o5OEI71a8'),
    names={row11: '蓝铁一键分基地（发电+低级电池）', row12: '蓝铁一键分基地（装备+杂物）'})
sets['set_032']['blueprints'] = items_to_bps('032', pick('EF01u28U74aea0aiAoOU', 'EF016u02EIeOe712O83e',
                                                       'EF0193aEOui5ieAi5uI2', 'EF01I43AU507097E5o08'))
sets['set_030']['description'] = '第一阶段紫晶过渡，适用于初始主基地。荞花准入口那边放荞花，另外一边放灌木。科技树：传送带分流、培植工艺、封装工艺、协议储存箱'
sets['set_031']['description'] = '第二阶段蓝铁过渡：分基地发电+低级电池要先放（一半低级电池发电一半可出售），分基地装备杂物放置比较复杂，建议看视频跟着摆。总需求130铁矿+90紫晶+210源矿。新增科技树：汇流器'
sets['set_032']['description'] = '第三阶段：蓝铁发电产线直接替换二阶段发电，加上一键砂叶+装备、一键四种零件、三合一进阶。总需求90铁矿+90紫晶+150源矿。新增科技树：研磨机'

# 2. MSC 力荐终极版：追加可替换版本、18紫药版、分基地小组件
s2 = sets['set_002']
have = {b['code'] for b in s2['blueprints']}
new2 = [it for it in sec('四号谷地', 'MSC力荐 —— 一键毕业终极版') if it['code'] not in have]
labels = {}  # 18紫药版这一组只有第一行有标签，后面几行补上
cur = None
for it in new2:
    if it.get('label'): cur = it['label']
    elif cur and '18紫药版' in cur: it['label'] = '可替换4+5+6+7+8捆绑 18紫药版'
names2 = {'EF01ao653IUOoA931oe5e': '8口紫胶囊（1）18紫药版', 'EF0170i86a43055UEO0Ai': '7口紫胶囊（2）18紫药版',
          'EF01o5uiE49e5638UIieO': '8口紫胶囊（3）18紫药版', 'EF01i1UI06Eo12e1O72U4': '零件模块 18紫药版',
          'EF01eaAo9128a4a38oAi8': '爆炸物模块 18紫药版'}
for it in new2:
    if it['code'] == 'EF01o5uiE49e5652I2eO': it['label'] = '可替换7+8捆绑'
s2['blueprints'] += items_to_bps('002', new2, names=names2, start=len(s2['blueprints']) + 1)
# 分基地小组件三行在原表里列是错开的（消耗写在效率列、产量写在发耗电列），按原意手动整理
howto = '摆放：先将分基地核心置于右下角，再向左移动3格，如图放置产线，对齐基地和准入口并调整基地出货口'
fix = {'EF01A67ua9OI6E339ieO': '分基地小组件1，' + howto,
       'EF01A67ua9OI6EEe9ieO': '分基地小组件2，消耗：120紫晶，' + howto,
       'EF01i1UI06Eo128i72U4': '分基地小组件3，消耗：30紫晶+30铁矿，效率：蓝铁瓶、钢制瓶各5，紫晶瓶15，24h产量：7200*2+21600，耗电：105，' + howto}
for b in s2['blueprints']:
    if b['code'] in fix: b['notes'] = fix[b['code']]

# 3. 新建的蓝图集
def new_set(num, name, region, desc, items, **kw):
    return {'id': f'set_{num}', 'name': name, 'author': 'MSC', 'region': region, 'location': '',
            'description': desc, 'blueprints': items_to_bps(num, items, **kw)}
copper = sec('1.4扩增武陵产线', '听说有人缺零件？')[0]
copper['fields']['name'] = '赤铜零件'
new_sets = [
    new_set('033', '武陵全产线模块合集', '武陵', '模块化的设计，在尚未毕业的阶段使用，主打缺什么补什么（需要手动调整出货口和放植物）',
            sec('武陵', '全产线模块蓝图合集') + [copper]),
    new_set('034', '【1.4】气体工业·视频版', '武陵', '一定要先推主线！裂隙不用填就能抄。按序号放置，详见视频',
            sec('1.4扩增武陵产线', '【1.4】气体工业·视频版')),
    new_set('035', '【1.4/1.5兼用】气体工业·究极毕业版', '武陵', '超传输1500致密源石粉末，按序号放置。应龙推荐接水方案',
            sec('1.4扩增武陵产线', '【1.4/1.5兼用】气体工业·究极毕业版')),
    new_set('036', '【1.3】无bug优化版本', '武陵', '对应进度：截止藏剑谷全部进度完成，地区探索等级达到17。超传输1500致密源石粉末。景玉谷两个模块和之前一样',
            sec('1.2+1.3扩增武陵产线', '【1.3】无bug优化版本')),
    new_set('037', '【1.3】新增小模块', '武陵', '在编号 A+B 的基建基础上增加，替换 A3/4',
            sec('1.2+1.3扩增武陵产线', '【1.3】新增小模块')),
    new_set('038', '【1.2下半】新增小模块', '武陵', '对应进度：截止实验园区开放，12天有烘炉。在编号 B/C 的基建基础上增加，超传输1500致密源石粉末',
            sec('1.2+1.3扩增武陵产线', '【1.2下半】新增小模块'),
            extra_notes={'EF0170i86a43055e6O0Ai': '耗电400 发电3200，放不下去记得旋转'}),
    new_set('039', '【1.2上半】视频版·一键毕业', '武陵', '对应进度：截止首墩开放，8天有烘炉。超传输1500致密源石粉末，按序号放置，详见视频',
            sec('1.2+1.3扩增武陵产线', '【1.2上半】视频版·一键毕业')),
    new_set('040', '【1.2上半】无bug·一键毕业', '武陵', '对应进度：截止首墩开放，8天有烘炉。超传输1500致密源石粉末。总计耗电4060 发电6600；死生模块为非必要省电小组件（模块作者：乾震_QzzZ）',
            sec('1.2+1.3扩增武陵产线', '【1.2上半】无bug·一键毕业')),
    new_set('041', '【1.1】视频版·一键毕业', '武陵', '超库存源石粉末1500。所有"一键"蓝图无需任何操作，不用调出货口，不用放植物，摆完即挂机，需要一定时间启动；"下"指河流方位在视图下方',
            sec('1.1扩增武陵产线', '视频版·汤汤也看得懂的一键毕业')),
    new_set('042', '【1.1】最高产率一键毕业', '武陵', '超库存蓝铁块（不是矿！）1500，需要满级主基地（包括二源桩）。装备药物模块有多个可替换版本，按需要的装备原件产量选一个。震荡发电组模块作者：乾震_QzzZ，放置完成后一定不能移动蓝图',
            sec('1.1扩增武陵产线', '最高产率一键毕业')),
    new_set('043', '活动·泡泡出击·下半（文档终极版）', '武陵', '使用前先拆除之前主基地和应龙关产线，景玉谷不动。前 3 个蓝图就是视频版。如需达到最高产能需要把雪松林的50息壤气拉到应龙',
            sec('活动产线', '文档终极版 泡泡出击·下半')),
    new_set('044', '活动·泡泡出击·上半（文档终极版）', '武陵', '使用前先拆除之前主基地和应龙关产线，景玉谷不动。前 2 个蓝图就是视频版。如需重息壤达到最高产能需要把雪松林的50息壤气拉到应龙',
            sec('活动产线', '文档终极版 泡泡出击·上半')),
    new_set('045', '活动·掌中救星·下半（急需代币可用）', '武陵', '超库存传输1500蓝铁块，使用前先拆除之前主基地和首墩产线，每天产518400代币。请确认自己已经解锁下半配方再使用',
            sec('活动产线', '掌中救星·下半（急需代币可用）')),
    new_set('046', '活动·掌中救星·上半', '武陵', '超库存传输1500蓝铁块，使用前先拆除之前主基地和首墩产线',
            sec('活动产线', '掌中救星·上半')),
    new_set('047', '新人入坑到毕业（武陵）', '武陵', '按武陵 1 → 2 → 2.5 → 3 阶段逐步替换，跟着自己的进度选',
            sec('新人入坑到毕业！', '新人入坑到毕业！')),
]
app['blueprintSets'] += new_sets
app['version'] = '1.1.0'
app['lastUpdated'] = '2026-10-07'
text = json.dumps(app, ensure_ascii=False, indent=2) + '\n'
open(sys.argv[3], 'w', encoding='utf-8').write(text)

# 检查：码字符合法、id 不重复、文档主表里的码全都在了
allb = [b for s in app['blueprintSets'] for b in s['blueprints']]
ids = [b['id'] for b in allb]; assert len(ids) == len(set(ids)), '蓝图 id 重复'
sids = [s['id'] for s in app['blueprintSets']]; assert len(sids) == len(set(sids)), '蓝图集 id 重复'
for b in allb:
    assert re.fullmatch(r'EF01[0-9aeiouAEIOU]{15,17}', b['code'].strip()), b
codes = {b['code'] for b in allb}
missing = [it['code'] for s in secs for it in s['items'] if it['code'] not in codes]
print('文档主表里没进 App 的码:', missing)
print('蓝图集', len(app['blueprintSets']), '蓝图', len(allb), '不重复的码', len(codes))
