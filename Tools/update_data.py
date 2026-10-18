#!/usr/bin/env python3
"""一键更新游戏数据（给定时任务用，Windows / macOS 都能跑）。

流程：拉取本仓库和解包仓库 → gen_datapack.py → 从森空岛补缺图 → gen_icons.py（两个脚本会自动更新
datapack_manifest.json）→ 安全检查 → 没问题就提交并推送到 GitHub(origin) 和 Gitee(gitee)。
推送到 main 就等于把数据发给了 App 用户（App 内更新，PLAN.md M5）。

安全检查：只有"只增不减"的更新（加配方、加物品、加图标）才自动推送。配方/物品/建筑/燃料有删除或改动、
出现新建筑或新分类时停下，改动留在工作区等人看；下次运行发现工作区不干净也会直接停下。

配置：复制 Tools/update_config.example.json 为 Tools/update_config.json（不进仓库）后填写。
退出码：0 没更新或已推送；2 停下等人确认；1 出错。
"""
import datetime
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / 'Tools'
OTHER = ROOT / 'EndfiledPlanner/other'
ORIGINALS = ROOT / '素材原图/物品'
LOG_DIR = TOOLS / 'update_logs'
DATA_FILES = ['recipes.json', 'items.json', 'devices.json', 'fuels.json', 'icon_fallbacks.json']
# 只提交这些位置，别的改动不碰
COMMIT_PATHS = ['EndfiledPlanner/other', '素材原图/物品', 'Tools/icon_report.json']

sys.stdout.reconfigure(encoding='utf-8', errors='replace')
LOG_DIR.mkdir(exist_ok=True)
LOG_PATH = LOG_DIR / f'{datetime.date.today().isoformat()}.log'

def log(*parts):
    line = ' '.join(str(p) for p in parts)
    print(line, flush=True)
    with LOG_PATH.open('a', encoding='utf-8') as f:
        f.write(line + '\n')

class Stop(Exception):
    """停下等人确认（退出码 2）"""

def run(args, cwd=ROOT, check=True):
    # 子进程强制 UTF-8：中文 Windows 默认编码是 GBK
    env = {**os.environ, 'PYTHONUTF8': '1', 'PYTHONIOENCODING': 'utf-8'}
    result = subprocess.run(args, cwd=cwd, env=env, capture_output=True, text=True, encoding='utf-8', errors='replace')
    output = (result.stdout + result.stderr).strip()
    if check and result.returncode != 0:
        raise RuntimeError(f'命令失败: {" ".join(map(str, args))}\n{output}')
    return output

def git(*args, cwd=ROOT, check=True):
    return run(['git', '-c', 'core.quotepath=false', *args], cwd=cwd, check=check)

def load_config():
    path = TOOLS / 'update_config.json'
    if not path.exists():
        raise RuntimeError('缺少 Tools/update_config.json，先复制 update_config.example.json 改好')
    cfg = json.loads(path.read_text(encoding='utf-8'))
    cfg['endfield_data'] = Path(cfg['endfield_data']).expanduser()
    if not (cfg['endfield_data'] / 'TableCfg').is_dir():
        raise RuntimeError(f'找不到解包数据: {cfg["endfield_data"] / "TableCfg"}')
    return cfg

def head_json(name):
    """git HEAD 里的版本（跟这次生成的比）"""
    text = git('show', f'HEAD:EndfiledPlanner/other/{name}', check=False)
    try:
        return json.loads(text)
    except ValueError:
        return None

def diff_by_id(old, new, key):
    old = {x[key]: x for x in old}
    new = {x[key]: x for x in new}
    added = sorted(new.keys() - old.keys())
    removed = sorted(old.keys() - new.keys())
    changed = sorted(k for k in old.keys() & new.keys() if old[k] != new[k])
    return added, removed, changed, new

def check_changes(before):
    """返回 (摘要行, 需要人确认的问题)"""
    summary, problems = [], []
    after = {name: json.loads((OTHER / name).read_text(encoding='utf-8')) for name in DATA_FILES}

    added, removed, changed, new = diff_by_id(before['recipes.json']['recipes'], after['recipes.json']['recipes'], 'id')
    if added:
        summary.append(f'新增配方 {len(added)} 条：' + '、'.join(
            f'{new[i]["machineName"]}→{new[i]["primaryOutcomeName"]}' for i in added))
    if removed:
        problems.append(f'有配方消失（旧存档里选了它们的建筑读档后会变成未设置）：{removed}')
    if changed:
        problems.append(f'有配方内容变了：{changed}')

    added, removed, changed, new = diff_by_id(before['items.json'], after['items.json'], 'itemId')
    if added:
        summary.append(f'新增物品 {len(added)} 个：' + '、'.join(new[i]['name'] for i in added))
    if removed or changed:
        problems.append(f'物品有删除或改动：删除 {removed}，改动 {changed}')

    old_dev, new_dev = before['devices.json'], after['devices.json']
    added, removed, changed, new = diff_by_id(old_dev['devices'], new_dev['devices'], 'id')
    if added:
        # 新建筑可能有特殊机制，App 代码不认识，必须人看（PLAN.md M5 "靠数据更新不了"）
        problems.append('出现新建筑：' + '、'.join(f'{i}（{new[i]["name"]}，{new[i]["categoryName"]}）' for i in added))
    if removed or changed:
        problems.append(f'建筑有删除或改动：删除 {removed}，改动 {changed}')
    if old_dev['categories'] != new_dev['categories']:
        problems.append('建筑分类有变化（新分类要改 BuildingParser.categoryMap）')

    old_icons = (head_json('datapack_manifest.json') or {}).get('icons', {})
    new_icons = json.loads((OTHER / 'datapack_manifest.json').read_text(encoding='utf-8'))['icons']
    added_icons = new_icons.keys() - old_icons.keys()
    changed_icons = [k for k in new_icons.keys() & old_icons.keys() if new_icons[k] != old_icons[k]]
    if added_icons or changed_icons:
        summary.append(f'图标新增 {len(added_icons)} 张、更新 {len(changed_icons)} 张')

    for name in ('fuels.json', 'icon_fallbacks.json'):
        if before[name] != after[name]:
            problems.append(f'{name} 有变化')
    return summary, problems

def missing_icon_names():
    """items.json 里在原图文件夹找不到图的物品（规则同 gen_icons.py；容器类借空容器的图，不算缺）"""
    have = {p.stem.rpartition('_')[0] for p in ORIGINALS.glob('*.png')}
    aliases = json.loads((TOOLS / 'icon_alias.json').read_text(encoding='utf-8'))
    items = json.loads((OTHER / 'items.json').read_text(encoding='utf-8'))
    return [i['name'] for i in items
            if '（已盛装' not in i['name'] and i['name'] not in have and aliases.get(i['name']) not in have]

def main():
    log('=' * 60)
    log('开始', datetime.datetime.now().isoformat(timespec='seconds'))
    cfg = load_config()
    data_dir = cfg['endfield_data']

    if git('status', '--porcelain'):
        raise Stop('工作区有没提交的改动（多半是上次停下等确认的更新），处理完再跑：\n' + git('status', '--short'))

    log('拉取本仓库…', git('pull', '--ff-only', 'origin', 'main'))
    old_commit = git('rev-parse', 'HEAD', cwd=data_dir)
    log('拉取解包数据…', git('pull', '--ff-only', cwd=data_dir))
    new_commit = git('rev-parse', 'HEAD', cwd=data_dir)
    log(f'解包数据 {old_commit[:7]} → {new_commit[:7]}')

    before = {name: head_json(name) for name in DATA_FILES}
    log(run([sys.executable, str(TOOLS / 'gen_datapack.py'), '--tablecfg', str(data_dir / 'TableCfg')]))

    names = missing_icon_names()
    still_missing = names
    if names:
        log(f'缺图 {len(names)} 个：' + '、'.join(names))
        if cfg.get('skland_did'):
            sys.path.insert(0, str(TOOLS))
            import skland_icons
            _, still_missing = skland_icons.download_missing(cfg['skland_did'], names, ORIGINALS)
        else:
            log('没配 skland_did，跳过下载')
    log(run([sys.executable, str(TOOLS / 'gen_icons.py'), '--tablecfg', str(data_dir / 'TableCfg')]))

    if not git('status', '--porcelain'):
        log('没有新数据，结束')
        return 0

    summary, problems = check_changes(before)
    if still_missing:
        summary.append('暂时没图（显示占位图）：' + '、'.join(still_missing))
    for line in summary:
        log('·', line)
    if problems:
        raise Stop('有需要确认的变化，没有推送：\n' + '\n'.join('！' + p for p in problems))
    if not cfg.get('auto_push', True):
        raise Stop('auto_push 关着，没有推送')

    git('add', '--', *COMMIT_PATHS)
    message = f'Data update from EndfieldData {new_commit[:7]}\n\n' + '\n'.join(summary)
    git('commit', '-m', message)
    for remote in cfg.get('remotes', ['origin', 'gitee']):
        log(f'推送 {remote}…', git('push', remote, 'HEAD:main'))
    log('已推送，App 用户可以在设置里更新到这份数据')
    return 0

if __name__ == '__main__':
    try:
        code = main()
    except Stop as stop:
        log(str(stop))
        log('改动留在工作区。看过没问题就自己提交推送；不要的话用 git checkout -- . 和 git clean -fd 撤掉')
        code = 2
    except Exception as error:
        log('出错：', error)
        code = 1
    log(f'日志：{LOG_PATH}')
    sys.exit(code)
