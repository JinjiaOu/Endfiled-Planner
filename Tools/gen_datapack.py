#!/usr/bin/env python3
"""Generate schema-1 factory data directly from the unpacked TableCfg repository."""
import argparse
import datetime
import json
from pathlib import Path
import subprocess

OVERRIDES = {"pump_1": {"keepRecipeIds": ["pump_1:0"]}, "excludedDevices": ["sp_sub_hub_1"]}
ROOT = Path(__file__).resolve().parents[1]
DEFAULT_TABLECFG = Path('/Users/owen/Desktop/Project/EndfieldData/TableCfg')
ENV_NAMES = {0: '', 1: '稳定环境', 2: '潮湿环境', 3: '酸性环境', 4: '息壤环境'}
LOGISTICS = [
    ('FactoryGridBeltTable', 'beltData', 'item_belt', '普通物流线'),
    ('FactoryGridRouterTable', 'gridUnitData', 'item_node', '普通物流节点'),
    ('FactoryBoxValveTable', 'gridUnitData', 'item_valve', '普通物流控流'),
    ('FactoryGridConnecterTable', 'gridUnitData', 'item_node', '普通物流节点'),
    ('FactoryLiquidPipeTable', 'pipeData', 'pipe', '管道线'),
    ('FactoryFluidValveTable', 'liquidUnitData', 'pipe_valve', '管道控流'),
    ('FactoryLiquidRouterTable', 'liquidUnitData', 'pipe_node', '管道节点'),
    ('FactoryLiquidConnectorTable', 'liquidUnitData', 'pipe_node', '管道节点'),
]

def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

def allowed(recipe):
    keep = OVERRIDES.get(recipe['machineId'], {}).get('keepRecipeIds')
    return keep is None or recipe['id'] in keep

def generate(tablecfg):
    def load(name):
        return json.loads((tablecfg / (name + '.json')).read_text(encoding='utf-8'))
    texts, items, buildings = load('I18nTextTable_CN'), load('ItemTable'), load('FactoryBuildingTable')
    def name(ref):
        return texts.get(str(ref.get('id')), ref.get('text', ''))
    containers = {}
    for table, empty, content in [('FullBottleTable', 'emptyBottleId', 'liquidId'), ('FullGasJarTable', 'emptyJarId', 'gasId')]:
        for key, row in load(table).items():
            containers[key] = (row[empty], row[content])
    def item(item_id, count):
        result = {'itemId': item_id, 'name': name(items[item_id]['name']), 'count': count}
        if item_id in containers:
            container_id, content_id = containers[item_id]
            container_name, content_name = name(items[container_id]['name']), name(items[content_id]['name'])
            result.update(name=f'{container_name}（已盛装{content_name}）', containerItemId=container_id,
                          containerItemName=container_name, contentItemId=content_id, contentItemName=content_name)
        return result
    def groups(values):
        return [item(x['id'], x['count']) for slot in values for x in slot['group']]
    recipes = []
    for key, r in load('FactoryMachineCraftTable').items():
        outputs = groups(r['outcomes'])
        recipes.append({'id': key, 'type': 'machineCraft', 'machineId': r['machineId'],
                        'machineName': name(buildings[r['machineId']]['name']),
                        'formulaGroupId': r['formulaGroupId'], 'seconds': r['totalProgress'] / 6000,
                        'progressRound': r['progressRound'], 'totalProgress': r['totalProgress'],
                        'sortId': r['sortId'], 'gasEnv': r['gasEnv'], 'gasEnvName': ENV_NAMES[r['gasEnv']],
                        'ingredients': groups(r['ingredients']), 'outcomes': outputs,
                        'primaryOutcomeName': outputs[0]['name'], 'sourceTable': 'FactoryMachineCraftTable.json'})
    for table, kind in [('FactoryMinerTable', 'mining'), ('FactoryFluidPumpInTable', 'pumping'),
                        ('FactoryGasMinerTable', 'gasMining')]:
        for machine_id, r in load(table).items():
            sources = r.get('mineable', [{'miningItemId': x, 'produceRate': 1} for x in r.get('enableLiquidIds', [])])
            for index, source in enumerate(sources):
                consume = source.get('consumeItem', {})
                outputs = [item(source['miningItemId'], source['produceRate'])]
                recipe = {'id': f'{machine_id}:{index}', 'type': kind, 'machineId': machine_id,
                          'machineName': name(buildings[machine_id]['name']), 'seconds': r['msPerRound'] / 1000,
                          'ingredients': [item(consume['id'], consume['count'])] if consume.get('count', 0) else [],
                          'outcomes': outputs, 'primaryOutcomeName': outputs[0]['name'], 'sourceTable': table + '.json'}
                if allowed(recipe):
                    recipes.append(recipe)
    recipes.sort(key=lambda x: x['id'])
    categories = [{'id': k, 'name': name(v['name']), 'priority': v['priority']}
                  for k, v in load('FactoryQuickBarTypeTable').items()]
    categories.append({'id': 'hub', 'name': '核心', 'priority': 101})
    categories.sort(key=lambda x: (-x['priority'], x['id']))
    category_names = {x['id']: x['name'] for x in categories}
    mode_names = load('FactoryMachineCraftModeTable')
    crafters = load('FactoryMachineCrafterTable')
    transmuters, vaporizers = load('FactoryTransmuterTable'), load('FactoryVaporizerTable')
    stations, hubs = load('FactoryPowerStationTable'), load('FactoryHubTable')
    def size(r):
        return {k: r.get(k, r.get({'width': 'x', 'depth': 'z', 'height': 'y'}.get(k, k), 0))
                for k in ('width', 'depth', 'height', 'x', 'y', 'z')}
    def ports(r, pipe=False):
        result = []
        for direction in ('input', 'output'):
            for index, port in enumerate(r.get(direction + 'Ports', [])):
                transform = port.get('trans', port)
                result.append({'index': port.get('index', index), 'direction': direction,
                               'kind': 'pipe' if port.get('isPipe', pipe) else 'item',
                               'position': transform['position'], 'rotation': transform['rotation']})
        return result
    def activation(r, kind, port):
        return {'type': kind, 'consumeItemId': r['consumeItem'], 'consumeItemName': name(items[r['consumeItem']]['name']),
                'minimumRatePerMinute': r['consumeRate'], 'maximumEffectiveRatePerMinute': r['consumeRateUpperLimit'],
                'activationPortIndex': port}
    devices = []
    for key, b in buildings.items():
        category = 'hub' if key == 'sp_hub_1' else b['quickBarType']
        if category not in category_names or key in OVERRIDES['excludedDevices']:
            continue
        crafter = crafters.get(key, {})
        modes = [{'id': m['modeName'], 'name': name(mode_names[m['modeName']]['machineModeTypeName']),
                  'defaultUnlocked': crafter['modeUnlockDefaultMap'].get(m['modeName'], False),
                  'isEnvMode': m['isEnvMode'], 'craftGroupId': m['groupName']} for m in crafter.get('modeMap', [])]
        requirements = []
        if key in transmuters:
            r = transmuters[key]
            requirements.append(activation(r, 'activator', r['consumeBindings']))
        if key in vaporizers:
            r = vaporizers[key]
            for group in r['groups']:
                a = activation(group, 'environmentGenerator', r['consumeBindings'])
                a.update(generatedEnvironmentId=group['genEnv'], generatedEnvironmentName=ENV_NAMES[group['genEnv']], rangeExtend=r['rangeExtend'])
                requirements.append(a)
        devices.append({'id': key, 'name': name(b['name']), 'recordType': 'building', 'categoryId': category,
                        'categoryName': category_names[category], 'buildingType': b['type'], 'size': size(b['range']),
                        'powerConsume': b['powerConsume'],
                        'powerGenerate': stations.get(key, {}).get('powerProvide', hubs.get(key, {}).get('powerGenerate', 0)),
                        'needPower': b['needPower'], 'liquidEnabled': b['liquidEnabled'], 'bandwidth': b['bandwidth'],
                        'modes': modes, 'activationRequirements': requirements, 'ports': ports(b), 'sourceTable': 'FactoryBuildingTable.json'})
    for table, data_key, kind, kind_name in LOGISTICS:
        for key, r in load(table).items():
            data = r[data_key]
            devices.append({'id': key, 'name': name(data['name']), 'recordType': 'logistic',
                            'logisticType': kind, 'logisticTypeName': kind_name,
                            'categoryId': 'logistic', 'categoryName': category_names['logistic'], 'size': size(r.get('range', {})),
                            'itemId': data['itemId'], 'speedSecondsPerRound': data['msPerRound'] / 1000,
                            'volume': data.get('volume'), 'powerGenerate': 0, 'ports': ports(r, kind.startswith('pipe')),
                            'sourceTable': table + '.json', 'modes': [], 'activationRequirements': []})
    devices.sort(key=lambda x: x['id'])
    used = {i['itemId'] for r in recipes for i in r['ingredients'] + r['outcomes']}
    item_rows = [{'itemId': k, 'name': item(k, 1)['name'],
                  'phase': 'liquid' if k.startswith('item_liquid_') else 'gas' if k.startswith('item_gas_') else 'solid'} for k in sorted(used)]
    assert len({i['name'] for i in item_rows}) == len(item_rows), 'Duplicate item names'
    common = {'schemaVersion': 1, 'source': 'EndfieldData/TableCfg', 'language': 'zh-CN'}
    return {'recipes.json': dict(common, recipes=recipes), 'devices.json': dict(common, categories=categories, devices=devices), 'items.json': item_rows}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tablecfg', type=Path, default=DEFAULT_TABLECFG)
    parser.add_argument('--output', type=Path, default=ROOT / 'EndfiledPlanner/other')
    args = parser.parse_args()
    pack = generate(args.tablecfg)
    assert pack == generate(args.tablecfg), 'Non-deterministic generation'
    args.output.mkdir(parents=True, exist_ok=True)
    commit = subprocess.check_output(['git', '-C', str(args.tablecfg), 'rev-parse', 'HEAD'], text=True).strip()
    meta_path = args.output / 'datapack_meta.json'
    # Preserve generation time when contents and source commit are unchanged.
    unchanged = all((args.output / file).exists() and json.loads((args.output / file).read_text()) == value for file, value in pack.items())
    previous = json.loads(meta_path.read_text()) if meta_path.exists() else {}
    timestamp = previous.get('generatedAt') if unchanged and previous.get('sourceCommit') == commit else None
    pack['datapack_meta.json'] = {'schemaVersion': 1, 'sourceCommit': commit,
                                 'generatedAt': timestamp or datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='seconds')}
    for file, value in pack.items():
        write_json(args.output / file, value)
    baseline = json.loads((ROOT / 'EndfiledPlanner/other/recipes_generated.json').read_text())['recipes']
    new = {r['id']: r for r in pack['recipes.json']['recipes']}
    old = {r['id']: r for r in baseline}
    removed = sorted(old.keys() - new.keys())
    changed = sorted(k for k in old.keys() & new.keys() if old[k] != new[k])
    added = sorted(new.keys() - old.keys())
    print(f'raw: removed={len(removed)}, changed={len(changed)}, added={len(added)}')
    print('overrideRemoved=' + json.dumps(removed, ensure_ascii=False))
    effective = {k: r for k, r in old.items() if allowed(r)}
    print(f'after overrides: removed={len(effective.keys() - new.keys())}, changed={len(changed)}, added={len(added)}')
    print('added=' + json.dumps(added, ensure_ascii=False))
    assert not (effective.keys() - new.keys()) and not changed
    experimental = [k for k in added if new[k]['type'] == 'machineCraft']
    gas = [r for r in new.values() if r['type'] == 'gasMining']
    assert len(experimental) == 12 and all('activity' in k for k in experimental)
    assert len(gas) == 2 and all(r['seconds'] == 3 for r in gas)
    devices = {d['id']: d for d in pack['devices.json']['devices']}
    assert 'sp_hub_1' in devices and 'sp_sub_hub_1' not in devices
    assert devices['power_station_1']['powerGenerate'] == 150 and devices['sp_hub_1']['powerGenerate'] == 200
    print('devices: sp_hub_1=true, sp_sub_hub_1=false, power_station_1.powerGenerate=150, sp_hub_1.powerGenerate=200')
    print(f'recipes={len(new)}, items={len(pack["items.json"])}, devices={len(devices)}, deterministic=true')

if __name__ == '__main__':
    main()
