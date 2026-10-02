#!/usr/bin/env python3
"""一次性生成旧存档迁移表 EndfiledPlanner/other/legacy_recipe_index.json。

旧版存档里 PlacedBuilding.selectedRecipeIndex/Indices 存的是"该建筑可选配方列表里的下标"，
列表来自已删除的 recipes.txt：按机器名分组、按第一个产物名排序，"（xx环境）"变体接在本机器后面，
水泵只留清水。这里按同样规则重建旧列表，再按 机器+环境+原料+产物+耗时 对到 recipes.json 的配方 ID。

recipes.txt 已从仓库删除，脚本从 git 历史里读（--commit 指定，默认是删除前最后一个提交）。
输出格式：{ "<建筑 id>": ["<配方 id>", ...] }，下标即旧下标；对不上的位置是 null。
"""
import argparse
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OTHER = ROOT / 'EndfiledPlanner' / 'other'


def parse_items(part):
    items = []
    for chunk in part.split('+'):
        chunk = chunk.strip()
        if not chunk:
            continue
        pieces = chunk.split('x')
        name = pieces[0].strip()
        count = int(pieces[1].strip()) if len(pieces) > 1 and pieces[1].strip().isdigit() else 1
        items.append((name, count))
    return items


def parse_recipes_txt(text):
    """复刻旧 RecipeViewModel.parseRecipes：按产物名分组，同一配方多产物会出现多次。"""
    by_output = {}
    for block in text.replace('\r\n', '\n').replace('\r', '\n').split('\n\n'):
        lines = [l.strip() for l in block.split('\n') if l.strip()]
        if len(lines) <= 1:
            continue
        for line in lines[1:]:
            if '|' not in line:
                continue
            left, right = line.split('|', 1)
            left_parts = left.strip().split(' ')
            if len(left_parts) < 2:
                continue
            time = int(left_parts[-1].replace('s', ''))
            machine = ' '.join(left_parts[:-1])
            if '->' not in right:
                continue
            inp, out = right.split('->')
            recipe = {'machine': machine, 'time': time,
                      'inputs': parse_items(inp.strip()), 'outputs': parse_items(out.strip())}
            if not recipe['outputs']:
                continue
            for name, _ in recipe['outputs']:
                by_output.setdefault(name, []).append(recipe)
    return by_output


def signature(r):
    i = '+'.join(f'{n}x{c}' for n, c in r['inputs'])
    o = '+'.join(f'{n}x{c}' for n, c in r['outputs'])
    return f"{r['machine']}|{r['time']}|{i}->{o}"


def recipes_by_machine(by_output):
    """复刻旧 recipesByMachine。Swift 里字典遍历顺序每次启动随机，同一机器下第一个产物同名的配方
    之间先后不确定；这里按文件顺序排，并把这种并列记下来报告。"""
    seen, result = set(), {}
    for recipes in by_output.values():
        for r in recipes:
            sig = signature(r)
            if sig in seen:
                continue
            seen.add(sig)
            result.setdefault(r['machine'], []).append(r)
    ties = []
    for machine, recipes in result.items():
        recipes.sort(key=lambda r: r['outputs'][0][0])
        names = [r['outputs'][0][0] for r in recipes]
        for n in set(names):
            if names.count(n) > 1:
                ties.append((machine, n))
    result['水泵'] = [r for r in result.get('水泵', []) if r['outputs'][0][0] == '清水']
    return result, ties


def split_env(machine):
    if '（' in machine and machine.endswith('环境）'):
        base, env = machine.split('（', 1)
        return base, env[:-1]
    return machine, None


def key_of(machine, env, time, inputs, outputs):
    return (machine, env or None, int(time), tuple(sorted(inputs)), tuple(sorted(outputs)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--commit', default='1601697')
    args = ap.parse_args()

    text = subprocess.check_output(
        ['git', 'show', f'{args.commit}:EndfiledPlanner/other/recipes.txt'], cwd=ROOT).decode('utf-8')
    machine_recipes, ties = recipes_by_machine(parse_recipes_txt(text))

    new = json.loads((OTHER / 'recipes.json').read_text())['recipes']
    new_by_key = {}
    for r in new:
        k = key_of(r['machineName'], r.get('gasEnvName'), r['seconds'],
                   [(i['name'], i['count']) for i in r['ingredients']],
                   [(o['name'], o['count']) for o in r['outcomes']])
        new_by_key.setdefault(k, []).append(r['id'])

    devices = json.loads((OTHER / 'devices.json').read_text())['devices']
    table, unmatched = {}, []
    for d in devices:
        name = d['name']
        old_list = list(machine_recipes.get(name, []))
        for variant in sorted(k for k in machine_recipes if k.startswith(name + '（')):
            old_list += machine_recipes[variant]
        if not old_list:
            continue
        ids = []
        for r in old_list:
            base, env = split_env(r['machine'])
            hits = new_by_key.get(key_of(base, env, r['time'], r['inputs'], r['outputs']), [])
            if len(hits) != 1:
                unmatched.append((d['id'], signature(r), hits))
                ids.append(None)
            else:
                ids.append(hits[0])
        table[d['id']] = ids

    out = OTHER / 'legacy_recipe_index.json'
    out.write_text(json.dumps(table, ensure_ascii=False, indent=2, sort_keys=True) + '\n')
    print(f'machines={len(table)}, entries={sum(len(v) for v in table.values())}, unmatched={len(unmatched)}')
    for u in unmatched:
        print('  unmatched', u)
    for machine, name in sorted(ties):
        print(f'  tie (旧排序不确定): {machine} / {name}')


if __name__ == '__main__':
    main()
