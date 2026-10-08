import json, re, sys
dump = json.load(open(sys.argv[1]))
app = json.load(open(sys.argv[2]))
code_owner = {}
for s in app['blueprintSets']:
    for b in s['blueprints']:
        code_owner[b['code'].strip()] = s['id']
PAT = re.compile(r'EF0\d[0-9A-Za-z]{10,}')
MAIN = ['四号谷地', '武陵', '1.4扩增武陵产线', '1.2+1.3扩增武陵产线', '1.1扩增武陵产线', '活动产线', '新人入坑到毕业！']
FIELD = {'名称': 'name', '蓝图码': 'code', '产物': 'product', '产物/min': 'product', '消耗材料（每分钟）': 'cost',
         '效率（每分钟）': 'rate', '24h产量': 'daily', '发耗电': 'power', '耗电': 'power', '占地': 'area', '备注': 'note',
         '一键毕业摆放方式': 'howto', '摆放参考图': 'howto', '序号': 'seq',
         '消耗材料': 'cost', '效率': 'rate', '固定数量产物': 'note'}
def col(ref): return re.match(r'[A-Z]+', ref).group(0)
def clean(v): return re.sub(r'\s+', ' ', v.replace('\n', ' / ')).strip()
sections = []
for sheet in MAIN:
    rows = dump[sheet]
    header = None; title = None; cur = None; pending_titles = []
    for row in rows:
        cells = {col(r): v for r, v in row}
        texts = [clean(v) for v in cells.values()]
        has_code = any(PAT.search(v) for v in cells.values())
        if not has_code and any(v.strip() in ('名称', '蓝图码') for v in cells.values()):
            header = {c: FIELD.get(clean(v), None) for c, v in cells.items()}
            title = pending_titles[-1] if pending_titles else sheet
            cur = {'sheet': sheet, 'title': title, 'items': []}
            sections.append(cur); pending_titles = []
            continue
        if not has_code:
            # 只有一两格文字的行当作潜在段落标题
            if 1 <= len(cells) <= 2 and len(texts[0]) <= 40:
                pending_titles.append(texts[0])
            continue
        if cur is None or (pending_titles and header is None):
            cur = {'sheet': sheet, 'title': pending_titles[-1] if pending_titles else sheet, 'items': []}
            sections.append(cur); header = header or {}
        item = {'label': None, 'fields': {}}
        for c, v in cells.items():
            f = (header or {}).get(c)
            # 1.2+1.3 这张表 B 列是系列字母、C 列是系列内序号，合起来就是表里"替换A3/4"说的编号
            if sheet == '1.2+1.3扩增武陵产线' and c in ('B', 'C'):
                item.setdefault('serial', {})[c] = clean(v)
                continue
            m = PAT.search(v)
            if m and 'code' not in item:
                item['code'] = m.group(0)
                continue
            if f in ('seq',) or (c == 'A' and f is None):
                item['label'] = clean(v)
            elif f:
                item['fields'][f] = clean(v)
            else:
                item['fields'].setdefault('extra', clean(v))
        item['owner'] = code_owner.get(item.get('code'))
        cur['items'].append(item)
json.dump(sections, open(sys.argv[3], 'w'), ensure_ascii=False, indent=1)
for i, s in enumerate(sections):
    owners = sorted({it['owner'] for it in s['items'] if it['owner']})
    new = [it for it in s['items'] if not it['owner']]
    print(f"[{i}] {s['sheet']} / {s['title']}  共{len(s['items'])} 已有{len(s['items'])-len(new)}{owners} 新{len(new)}")
    for it in new:
        print('     +', it.get('label') or '', '|', it['fields'].get('name', ''), '|', it['code'])
