#!/usr/bin/env python3
"""Check i18n data/catalog invariants; --runtime compares unchanged Swift algorithms in zh/en (macOS)."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import plistlib
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
OTHER = ROOT / 'EndfiledPlanner/other'


def read(path):
    return json.loads(path.read_text(encoding='utf-8'))


def check_data():
    path = OTHER / 'names_en.json'
    names = read(path)
    assert set(names) == {'items', 'devices', 'categories', 'modes'}
    assert list(names) == sorted(names)
    for entries in names.values():
        assert list(entries) == sorted(entries)
        assert all(isinstance(value, str) and value.strip() for value in entries.values())
    assert names['categories']['hub'] == 'Core'
    expected = (json.dumps(names, ensure_ascii=False, indent=2) + '\n').encode('utf-8')
    assert path.read_bytes() == expected, 'names_en must use deterministic UTF-8/LF serialization'
    entry = read(OTHER / 'datapack_manifest.json')['files']['names_en.json']
    assert entry == {'sha256': hashlib.sha256(expected).hexdigest(), 'size': len(expected)}
    print('PASS: sorted English names, UTF-8/LF bytes, and manifest checksum')


def check_catalog():
    catalog = read(OTHER / 'Localizable.xcstrings')
    assert catalog['sourceLanguage'] == 'zh-Hans'
    placeholder = re.compile(r'%(?:(\d+)\$)?(lld|ld|d|@|\.\d+f|f)')

    def arguments(text):
        return sorted((int(position) if position else index, kind)
                      for index, (position, kind) in enumerate(placeholder.findall(text.replace('%%', '')), 1))

    for key, record in catalog['strings'].items():
        english = record['localizations']['en']
        if 'substitutions' in english:
            subs = english['substitutions']
            used = sorted([(value['argNum'], value['formatSpecifier']) for value in subs.values()]
                          + arguments(english['stringUnit']['value']))
            assert used == arguments(key), (key, used)
            assert all('one' in value['variations']['plural'] and 'other' in value['variations']['plural'] for value in subs.values())
        else:
            units = ([english['stringUnit']] if 'stringUnit' in english else
                     [value['stringUnit'] for value in english['variations']['plural'].values()])
            for unit in units:
                assert unit['state'] == 'translated' and unit['value'].strip(), key
                assert arguments(key) == arguments(unit['value']), (key, unit['value'])
    print(f"PASS: {len(catalog['strings'])} English catalog entries and format arguments")


def check_runtime():
    app = ROOT / 'EndfiledPlanner'
    files = [
        'RecipeSearch/Model/Recipe.swift', 'RecipeSearch/Model/RecipeNode.swift',
        'RecipeSearch/Model/ItemCatalog.swift', 'RecipeSearch/Model/DisplayName.swift',
        'RecipeSearch/ViewModel/RecipeViewModel.swift',
        'ProductionOptimizer/ViewModel/FactoryBuilding.swift',
        'ProductionOptimizer/ViewModel/BuildingParser.swift',
        'ProductionOptimizer/ViewModel/FactoryGridModel.swift',
        'ProductionOptimizer/ViewModel/MapRules.swift',
        'ProductionOptimizer/ViewModel/FlowSimulator.swift',
        'Calculator/ProductionCalculator.swift',
    ]
    with tempfile.TemporaryDirectory(prefix='endfield-i18n-') as tmp:
        tmp = Path(tmp)
        bundle = tmp / 'Verify.app/Contents'
        (bundle / 'MacOS').mkdir(parents=True)
        (bundle / 'Resources').mkdir()
        (bundle / 'Info.plist').write_bytes(plistlib.dumps({
            'CFBundleIdentifier': 'local.EndfieldI18nVerification',
            'CFBundleExecutable': 'verify', 'CFBundleDevelopmentRegion': 'zh-Hans',
            'CFBundleLocalizations': ['zh-Hans', 'en'], 'CFBundlePackageType': 'APPL',
        }))
        subprocess.run(['xcrun', 'xcstringstool', 'compile', str(OTHER / 'Localizable.xcstrings'),
                        '--output-directory', str(bundle / 'Resources')], check=True)
        binary = bundle / 'MacOS/verify'
        subprocess.run(['swiftc', '-module-cache-path', str(tmp / 'modules'),
                        *[str(app / path) for path in files],
                        str(ROOT / 'Tools/i18n_checks/DataPackStore.swift'),
                        str(ROOT / 'Tools/i18n_checks/main.swift'), '-o', str(binary)], check=True)
        for language in ['zh-Hans', 'en']:
            subprocess.run([str(binary), str(OTHER), str(tmp / (language + '.json')),
                            '-AppleLanguages', '(' + language + ')'], check=True)
        assert (tmp / 'zh-Hans.json').read_bytes() == (tmp / 'en.json').read_bytes()
        missing_names = tmp / 'without-names'
        missing_names.mkdir()
        for path in OTHER.glob('*.json'):
            if path.name != 'names_en.json':
                shutil.copyfile(path, missing_names / path.name)
        subprocess.run([str(binary), str(missing_names), str(tmp / 'fallback.json'),
                        '-AppleLanguages', '(en)'], check=True)
        assert (tmp / 'fallback.json').read_bytes() == (tmp / 'en.json').read_bytes()
        result = read(tmp / 'en.json')
        assert result['preset_valley4_battery']['outputs']['高容谷地电池'] == 6
        assert result['preset_wuling_equip']['outputs']['灼铜装备原件'] == 6
        for preset in ['preset_valley4_battery', 'preset_wuling_equip']:
            assert result[preset]['converged'] and result[preset]['unpowered'] == 0
        assert result['calculator']['totalMachines'] == 90
        assert result['calculator']['powerMW'] == 2080
        print('PASS: both presets, Chinese-save round trip, bilingual search, missing-file fallback, plurals, map display, and calculator match in zh/en')
        print(json.dumps({k: {n: v[n] for n in ['buildingCount', 'powerConsumed', 'powerGenerated']} for k, v in result.items() if k.startswith('preset_')}, ensure_ascii=False))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runtime', action='store_true', help='Compile and run Swift models on macOS')
    args = parser.parse_args()
    check_data()
    check_catalog()
    if args.runtime:
        check_runtime()
