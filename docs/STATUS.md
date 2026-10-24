# 当前状态（STATUS）

> **新会话先读这个文件。** 本文件只描述“现在”，每次有进展就覆盖更新；历史和证据在 [`LOG.md`](LOG.md)。
> 最后更新：2026-10-25（CST）· 当前分支 `autoresearch/oct25-4090d`（从 `repro/wsl-remote-4090` 拉出）

## 1. 一句话结论

在远程 RTX 4090 D 上复现 autoresearch baseline：**环境 ✅ 数据 ✅ 训练 ✅，baseline val_bpb = 1.122878**。前两台 4090 是显存硬件故障，不是代码问题（LOG L2、L3）。

## 2. 任务看板

| # | 任务 | 状态 | 关键结果 | 详情 |
|---|---|---|---|---|
| 1 | 环境配置 | ✅ | `.venv` 复用系统 torch 2.11.0+cu128，GPU sm_89；显存测试 0 错误 | LOG L4 |
| 2 | `prepare.py`（数据 + tokenizer） | ✅ | 11 个分片，tokenizer vocab=8192，`PREP_EXIT=0` | LOG L6 |
| 3 | `train.py` baseline | ✅ | **val_bpb 1.122878**，260 步，峰值显存 11.4 GB，0 次 NaN，`TRAIN_EXIT=0` | LOG L7、L9 |
| 4 | baseline 记入 `results.tsv` | ✅ | 远程 `/root/autoresearch/results.tsv`（不进 git） | LOG L9 |
| 5 | `program.md` 自主实验循环（教学用，约 1 小时 / 约 8 个实验） | ⏳ 进行中 | 分支 `autoresearch/oct25-4090d`；实验记录在远程 `results.tsv` | LOG L10 |

## 3. 机器与路径

| 位置 | 路径 | 说明 |
|---|---|---|
| 本地 WSL | `/home/lxx/projects/autoresearch` | 没有 GPU；三边同步的中转站 |
| GitHub | `origin` = `https://github.com/SerenLi95/autoresearch.git` | 分支 `repro/wsl-remote-4090` |
| 远程 GPU | SSH 别名 `ZCY-4090`（root@hb01-ssh.gpuhome.cc:30139） | RTX 4090 D 24 GB，22 核，100 GB 内存 |
| 远程代码 + `.venv` | `/root/autoresearch`（系统盘，会随镜像保存） | |
| 远程数据 + 缓存 | `/root/rivermind-data/cache`（数据盘，**不会随镜像保存**） | `~/.cache/autoresearch` 是指向这里的软链接 |
| 远程运行日志 | `/root/autoresearch/run.log`；`/root/tools/*.log` | 不进 git |

已经弃用的机器：`bitahub-4090`、`BH-4090`，显存硬件故障，不要再用。

## 4. 怎么接着干（新会话照做）

```bash
# 0) 本地：确认三边一致（应输出同一个 hash，共三行）
cd /home/lxx/projects/autoresearch && git fetch -q origin && git fetch -q zcy
for r in HEAD origin/repro/wsl-remote-4090 zcy/repro/wsl-remote-4090; do git rev-parse --short $r; done

# 1) 远程：~/.bashrc 已经自动 source tools/env.sh，直接用即可
ssh ZCY-4090 'cd /root/autoresearch && git status -sb && tail -3 run.log'
ssh ZCY-4090 'grep "^val_bpb:\|^peak_vram_mb:" /root/autoresearch/run.log'

# 2) 跑一个实验（本地执行：推送当前 HEAD → 远程训练 → 打印结果，约 7 分钟）
sh tools/run_remote.sh
```

**新实例 / 数据盘被清空后**，按顺序执行：
`sh tools/setup_env.sh` → `sh tools/fetch_shards.sh` → `uv run prepare.py` → `sh tools/fetch_fa3.sh` → `uv run train.py`。
换了新 GPU，先跑 `python3 -I tools/vram_dma_test.py 1 0 check`，确认 0 错误再训练。

## 5. 三边同步规则

本地 commit → `git push origin` → `git push zcy` → 用上面的第 0 步检查三边一致。
**远程连不上 GitHub，不要在远程执行 `git pull`。** 远程如果有未提交的改动，`git push zcy` 会被拒绝（`updateInstead` 机制），先处理掉再推。

## 6. 已知坑（踩过的）

- 不要在远程直接 `uv sync`：会去装锁定的 torch 2.9.1。要用 `tools/setup_env.sh`。`uv run` 能用，前提是 `env.sh` 设了 `UV_NO_SYNC=1`。
- 不要在 SSH 命令里写 `pkill -f "xxx"`，会把这条 SSH 会话自己也杀掉。改用 `pkill -f "[x]xx"`。
- `huggingface_hub` 走 hf-mirror 下载大文件会卡住，大文件用 `tools/fetch_fa3.sh` 的方式下载（分段 curl + sha256 校验）。
- `prepare.py` 只读，不能修改（`program.md` 规定）。数据访问问题靠预先下载分片绕过。

## 7. 未决问题 / 风险（需要用户知道或决定）

1. **torch 版本偏差**：实际运行的是 2.11.0，而锁定的是 2.9.1（为了遵守“不要重复下载 PyTorch”）。baseline 数值可能和上游有细微差别；同一台机器上做前后实验对比不受影响。
2. `train.py` 打印的 MFU 是按 H100 峰值算力计算的，在 4090 上只能做相对参考。
3. 你给的运行命令里有 `NO_COMPILE=1`，但 `train.py` 并不读取这个变量。如果确实需要关闭编译，要另外加代码。
4. 4090 在 5 分钟里只能跑 260 步（`program.md` 的 H100 示例是 953 步），所以 baseline bpb 比示例里的 0.998 高。之后的实验应该和 **1.122878** 比，不要和 H100 的数字比。
