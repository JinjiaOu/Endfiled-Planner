# 自动更新游戏数据（Windows 定时任务）

`Tools/update_data.py` 一次做完：拉取解包数据 → 生成配方/物品/建筑 → 从森空岛补缺图 → 生成图标和清单 → 检查 → 提交并推送到 GitHub 和 Gitee。推送到 main 后，App 用户在设置里就能更新到（PLAN.md M5）。

只有"只增不减"的更新会自动推送。有配方/物品/建筑删除或改动、出现新建筑或新分类时会停下，改动留在工作区，日志里写明原因。

## 一次性准备

1. 装 [Python 3](https://www.python.org/downloads/)（勾选 Add to PATH）和 [Git for Windows](https://git-scm.com/download/win)，然后：
   ```
   py -m pip install pillow
   ```
2. 找一个文件夹（放哪都行），在里面打开命令行，把两个仓库克隆成并排的两个子文件夹：
   ```
   git clone https://github.com/rmxlinux/EndfieldData.git EndfieldData
   git clone -c core.autocrlf=false https://github.com/JinjiaOu/Endfiled-Planner.git EndfiledPlanner
   cd EndfiledPlanner
   git remote add gitee https://gitee.com/JinjiaOu/endfield--planner.git
   git config user.name "JinjiaOu"
   git config user.email "你的邮箱"
   ```
   （`core.autocrlf=false` 要在克隆时就加：清单里记的是文件的 sha256，换行符被 Git 改成 CRLF 会对不上。）
3. 推送权限：在这台电脑上手动推一次 `git push origin main` 和 `git push gitee main`，Git Credential Manager 会弹窗登录，之后就记住了（Gitee 用账号密码或私人令牌）。
4. 复制 `Tools\update_config.example.json` 为 `Tools\update_config.json`（这个文件不进仓库），填好：
   - `endfield_data`：解包仓库路径，相对本仓库根目录算。按第 2 步并排放的话保持默认 `../EndfieldData` 不用改
   - `skland_did`：森空岛 DID（在这台电脑跑 End-WikiPlus 拿到的）。留空就不自动下图标
   - `auto_push`：`false` 时只生成不推送
5. 在 `EndfiledPlanner` 文件夹里手动跑一次看看：
   ```
   py Tools\update_data.py
   ```

## 设定时任务

任务计划程序 → 创建基本任务 → 每天（比如早上 9 点）→ 启动程序：
- 程序：`py`
- 参数：`Tools\update_data.py`
- 起始于：`EndfiledPlanner` 文件夹的完整路径（任务计划程序只认完整路径，这一处没法用相对路径）

## 结果怎么看

日志在 `Tools\update_logs\日期.log`。退出码：
- `0`：没有新数据，或已经推送
- `2`：停下等你确认。看日志里"！"开头的原因：没问题就自己 `git add` / `commit` / `push`；不要的话 `git checkout -- .` 加 `git clean -fd` 撤掉。不处理的话，之后每次运行都会直接停下
- `1`：出错（网络、脚本报错等），看日志
