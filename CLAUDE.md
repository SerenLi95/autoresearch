## 语言规范
- 所有回复、解释、报错说明必须使用简体中文。
- 代码、命令、变量名等技术术语保持英文原文。

## 项目背景
- 这是教学项目：目的是学会用 AI 工具驱动 AutoResearch 流程，不追求 val_bpb 有多好。实验循环保持短（约 1 小时）。
- 实验规则以 `program.md` 为准（只改 `train.py`，`prepare.py` 只读）。

## 开工前
- 先读 `docs/STATUS.md`（当前状态、怎么接着干）和 `docs/ROADMAP.md`（项目阶段）。

## 项目记录规范
- 主线分支是 `repro/wsl-remote-4090`，文档以它为准；`master` 与上游保持一致，不放文档。
- 实验分支从主线拉出，结束后用 `git checkout <实验分支> -- docs/ tools/` 把文档合回主线，不带入实验改过的 `train.py`。
- 执行会话每完成一个阶段性步骤：覆盖更新 STATUS，向 LOG 追加一条（只追加，不改历史），commit 后做三边同步（STATUS 第 5 节）。
- `docs/ROADMAP.md` 只由总控（orchestrator）会话维护；两个会话不同时写同一个文件。

## 环境硬规则
- 本地没有 GPU，训练都在远程跑（用 `sh tools/run_remote.sh`）。远程连不上 GitHub，不要在远程 `git pull`，由本地中转同步。
- 远程不要直接 `uv sync`，也不要重新下载或编译 PyTorch；要用 `tools/setup_env.sh`。
- 换新 GPU 先跑显存测试（STATUS 第 4 节），0 错误才训练。
- SSH 命令里杀进程要写成 `pkill -f "[t]rain.py"`，避免把自己的 SSH 会话也杀掉。

## 需要先问用户的操作
- 关机或释放实例、删除远程数据、对主线 force push、修改 `program.md` / `prepare.py`。
