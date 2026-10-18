#!/usr/bin/env python3
"""从森空岛百科（wiki.skland.com，终末地百科 → 物品）下载缺图物品的原图。

接口签名照搬用户的抓取脚本。DID 是用户自己设备生成的，只写在本地配置
Tools/update_config.json（不进仓库）。文件存成 `名称_森空岛itemId.png`，跟 素材原图/物品 里的命名一致。
"""
import hashlib
import hmac
import json
import time
import urllib.parse
import urllib.request
import uuid
from pathlib import Path

HOST = 'https://zonai.skland.com'
HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                  '(KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36',
    'Referer': 'https://wiki.skland.com/',
    'Origin': 'https://wiki.skland.com',
    'Accept': '*/*',
}

def _get(url, headers, timeout=60):
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read()

def _token(did):
    data = json.loads(_get(HOST + '/web/v1/auth/refresh', {**HEADERS, 'Did': did}))
    if data.get('code') != 0:
        raise RuntimeError(f'森空岛刷新 Token 失败: {data}')
    token = data['data']
    return token['token'] if isinstance(token, dict) else token

def _signed_get(did, token, path, params):
    query = urllib.parse.urlencode(params)
    timestamp = str(int(time.time()))
    sign_headers = json.dumps({'platform': '3', 'timestamp': timestamp, 'dId': did, 'vName': '1.0.0'},
                              separators=(',', ':'), ensure_ascii=False)
    digest = hmac.new(token.encode(), (path + query + timestamp + sign_headers).encode(), hashlib.sha256).hexdigest()
    headers = {**HEADERS, 'Cred': uuid.uuid4().hex, 'Did': did, 'Sign': hashlib.md5(digest.encode()).hexdigest(),
               'Timestamp': timestamp, 'Platform': '3', 'Vname': '1.0.0', 'Content-Type': 'application/json'}
    data = json.loads(_get(f'{HOST}{path}?{query}', headers))
    if data.get('code') != 0:
        raise RuntimeError(f'森空岛接口出错: {data}')
    return data

def catalog(did):
    """名称 → (森空岛 itemId, 图片地址)"""
    data = _signed_get(did, _token(did), '/web/v1/wiki/item/catalog', {'typeMainId': '1', 'typeSubId': '6'})
    found = {}
    def walk(value):
        if isinstance(value, dict):
            brief = value.get('brief')
            if value.get('itemId') and value.get('name') and isinstance(brief, dict) and brief.get('cover'):
                found[str(value['name'])] = (str(value['itemId']), brief['cover'].strip())
            for child in value.values():
                walk(child)
        elif isinstance(value, list):
            for child in value:
                walk(child)
    walk(data)
    return found

def download_missing(did, names, out_dir: Path):
    """下载 names 里在森空岛有图的物品，返回 (下载到的名称列表, 森空岛也没有的名称列表)"""
    if not names:
        return [], []
    found = catalog(did)
    got = []
    for name in sorted(names):
        if name not in found:
            continue
        item_id, url = found[name]
        if not urllib.parse.urlparse(url).path.lower().endswith('.png'):
            print(f'  跳过 {name}: 不是 png（{url}）')
            continue
        data = _get(url, {'User-Agent': HEADERS['User-Agent'], 'Referer': HEADERS['Referer']})
        (out_dir / f'{name}_{item_id}.png').write_bytes(data)
        got.append(name)
        print(f'  下载 {name} ({item_id}, {len(data)} bytes)')
        time.sleep(1.0)
    return got, sorted(set(names) - set(got))
