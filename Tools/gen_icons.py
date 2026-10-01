#!/usr/bin/env python3
"""Generate compact item asset catalogs and report deterministic wiki matches."""
import argparse
from collections import defaultdict
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_TABLECFG = Path('/Users/owen/Desktop/Project/EndfieldData/TableCfg')

def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tablecfg', type=Path, default=DEFAULT_TABLECFG)
    parser.add_argument('--items', type=Path, default=ROOT / 'EndfiledPlanner/other/items.json')
    parser.add_argument('--originals', type=Path, default=ROOT / '素材原图/物品')
    parser.add_argument('--output', type=Path, default=ROOT / 'EndfiledPlanner/other/ItemIcons.xcassets')
    args = parser.parse_args()
    items = json.loads(args.items.read_text())
    aliases = json.loads((ROOT / 'Tools/icon_alias.json').read_text())
    wiki = defaultdict(list)
    for path in sorted(args.originals.glob('*.png')):
        wiki_name, separator, number = path.stem.rpartition('_')
        if not separator or not number.isdigit():
            raise ValueError(f'Invalid wiki image name: {path.name}')
        wiki[wiki_name].append(path)
    def match(name):
        # Prefer the lowest wiki number if several images share a wiki name.
        paths = wiki.get(name) or wiki.get(aliases.get(name, ''))
        return min(paths, key=lambda p: (int(p.stem.rpartition('_')[2]), p.name)) if paths else None
    names = {x['name']: x['itemId'] for x in items}
    textures, used = {}, set()
    report = {'matched': [], 'fallback': {}, 'unmatched': [], 'wikiUnused': []}
    for row in sorted(items, key=lambda x: x['itemId']):
        item_id, name = row['itemId'], row['name']
        source = match(name)
        if source:
            report['matched'].append(item_id)
        elif '（已盛装' in name:
            base_name = name.split('（已盛装', 1)[0]
            source = match(base_name)
            if source:
                report['fallback'][item_id] = names[base_name]
        if source:
            textures[item_id] = source
            used.add(source)
        else:
            report['unmatched'].append({'itemId': item_id, 'name': name})
    table = json.loads((args.tablecfg / 'ItemTable.json').read_text())
    texts = json.loads((args.tablecfg / 'I18nTextTable_CN.json').read_text())
    game_names = defaultdict(list)
    for key, row in table.items():
        if not key.startswith('sysbp_'):
            game_names[texts.get(str(row['name']['id']), row['name'].get('text', ''))].append(key)
    for wiki_name in sorted(wiki):
        ids = game_names.get(wiki_name, [])
        if len(ids) == 1:
            source = match(wiki_name)
            textures.setdefault(ids[0], source)
            used.add(source)
    report['wikiUnused'] = sorted(p.name for paths in wiki.values() for p in paths if p not in used)
    # Stage the complete catalog before replacing the generated output, so stale assets disappear.
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=args.output.parent, prefix='.item-icons-') as temporary:
        catalog = Path(temporary) / args.output.name
        catalog.mkdir()
        write_json(catalog / 'Contents.json', {'info': {'author': 'xcode', 'version': 1}})
        for item_id, source in sorted(textures.items()):
            folder = catalog / (item_id + '.imageset')
            folder.mkdir()
            subprocess.run(['sips', '-Z', '192', str(source), '--out', str(folder / 'icon.png')],
                           check=True, stdout=subprocess.DEVNULL)
            # A 256-colour transparent palette keeps the full 192px silhouette compact.
            with Image.open(folder / 'icon.png') as image:
                image.convert('RGBA').quantize(colors=256, method=Image.Quantize.FASTOCTREE,
                                               dither=Image.Dither.NONE).save(folder / 'icon.png', optimize=True)
            write_json(folder / 'Contents.json', {'images': [{'filename': 'icon.png', 'idiom': 'universal', 'scale': '1x'}],
                                                  'info': {'author': 'xcode', 'version': 1}})
        size = sum(p.stat().st_size for p in catalog.rglob('*') if p.is_file())
        assert size < 6 * 1024 * 1024, f'Catalog exceeds 6 MiB: {size}'
        if args.output.exists():
            shutil.rmtree(args.output)
        shutil.move(str(catalog), str(args.output))
    write_json(ROOT / 'Tools/icon_report.json', report)
    print(f'matched={len(report["matched"])}, fallback={len(report["fallback"])}, unmatched={len(report["unmatched"])}, wikiUnused={len(report["wikiUnused"])}')
    print(f'imagesets={len(textures)}, bytes={size}, sizeMB={size / 1_000_000:.3f}, below6MB={size < 6_000_000}')
    print(f'originalsMoved={not (ROOT / "EndfiledPlanner/物品").exists()}')
    assert not report['unmatched'], report['unmatched']
    assert size < 6_000_000

if __name__ == '__main__':
    main()
