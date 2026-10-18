#!/usr/bin/env python3
"""Write EndfiledPlanner/other/datapack_manifest.json for in-app data updates.

App 内更新（M5）读这份清单：每个可更新的 JSON 和每个物品图标的 sha256/大小。
gen_datapack.py 和 gen_icons.py 跑完会自动调用；也可以单独跑。
"""
import datetime
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OTHER = ROOT / 'EndfiledPlanner/other'
# 数据包格式版本：App 只接受不高于自己认识的版本（DataPackStore.supportedFormat），字段结构变了才加
FORMAT_VERSION = 1
# 能下发的数据文件。legacy_recipe_index.json 是旧存档一次性迁移表，不会再变，不下发
FILES = ['recipes.json', 'items.json', 'devices.json', 'fuels.json', 'icon_fallbacks.json']

def entry(path):
    data = path.read_bytes()
    return {'sha256': hashlib.sha256(data).hexdigest(), 'size': len(data)}

def write_manifest(other=OTHER):
    files = {name: entry(other / name) for name in FILES}
    icons = {p.parent.stem: entry(p) for p in sorted((other / 'ItemIcons.xcassets').glob('*.imageset/icon.png'))}
    # 内容指纹：文件或图标有任何变化才换版本号
    digest = hashlib.sha256(json.dumps([files, icons], sort_keys=True).encode()).hexdigest()[:16]
    meta = json.loads((other / 'datapack_meta.json').read_text(encoding='utf-8'))
    path = other / 'datapack_manifest.json'
    previous = json.loads(path.read_text(encoding='utf-8')) if path.exists() else {}
    # builtAt 是 App 比新旧用的；内容没变就沿用旧时间，避免每次重跑都让用户"有更新"
    built_at = previous.get('builtAt') if previous.get('dataVersion') == digest else None
    manifest = {'formatVersion': FORMAT_VERSION, 'dataVersion': digest,
                'builtAt': built_at or datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='seconds'),
                'sourceCommit': meta.get('sourceCommit'), 'files': files, 'icons': icons}
    path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
    print(f'manifest: dataVersion={digest}, builtAt={manifest["builtAt"]}, files={len(files)}, icons={len(icons)}')

if __name__ == '__main__':
    write_manifest()
