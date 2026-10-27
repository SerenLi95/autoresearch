# 项目路线图（ROADMAP）

> **项目级视角：目标、阶段、下一步。** 由总控会话（orchestrator）维护；每个阶段开始标 ⏳，结束标 ✅ 并写一行结论。
> 当前阶段的细节看 [`STATUS.md`](STATUS.md)，历史和证据看 [`LOG.md`](LOG.md)。
> 最后更新：2026-10-27（L13：CLAUDE.md 纳入版本管理）

## 项目目标

借 karpathy/autoresearch 这个教学项目，**学会用 AI 工具（Claude Code）驱动 AutoResearch 的完整工作流程**：远程 GPU 环境、自主实验循环、记录与对齐、三边同步。结果好坏是次要的，流程走通、能复盘才是目标。

## 分工与文档规则

| 角色 | 会话 | 职责 | 写哪些文件 |
|---|---|---|---|
| 总控（orchestrator） | 右窗格 | 跟进全局、排优先级、检查记录和同步 | 只写 `ROADMAP.md` |
| 执行（worker） | 左窗格 | 做当前阶段的具体任务 | `STATUS.md`（覆盖）、`LOG.md`（追加）、代码 |

- **主线分支 `repro/wsl-remote-4090`**：文档以它为准。实验分支从主线拉出；实验结束后，只把 `docs/` 和 `tools/` 合回主线，不带实验改过的 `train.py`。
- `master` 保持与上游 karpathy 一致，不放文档。
- 两个会话不同时写同一个文件。

## 阶段

| # | 阶段 | 状态 | 结论 | 详情 |
|---|---|---|---|---|
| P1 | bitahub-4090 / BH-4090 上跑通 baseline | ✅ 放弃 | OOM 已修（batch 128→32）；NaN 是显存物理损坏，两台都不能用 | LOG L1–L3 |
| P2 | ZCY-4090 环境 + 数据 + baseline | ✅ | 复用系统 torch 2.11；baseline val_bpb **1.122878** | LOG L4–L9 |
| P3 | 记录与同步机制 | ✅ | STATUS / LOG 双文件 + 三边同步（本地中转） | LOG L8 |
| P4 | 自主实验循环（教学用，约 1 小时） | ✅ | 8 个实验，最好 **1.099618**（`d01c2b3`，−0.0233） | LOG L10–L11 |
| P5 | 总控 / 执行双会话分工，文档收归主线 | ✅ | 新增本文件；docs 合回 `repro/wsl-remote-4090` | LOG L12 |

## 下一阶段候选（由用户选）

- [ ] 继续实验循环：`DEPTH` 4/5；用 3 个种子复核实验 6、7；在小模型上重调 `TOTAL_BATCH_SIZE`（见 LOG L11 末尾）
- [ ] 让 AI 完全自主跑一轮（不中途干预），对比和这次“人盯着”的区别
- [ ] 复盘整套流程，整理成自己的 AutoResearch 操作手册

## 待用户处理

- 远程 ZCY-4090 已关机。开机后：SSH 地址如有变化，更新 `~/.ssh/config` 的 `ZCY-4090` 和 git remote `zcy`，再把主线推过去（`git push zcy repro/wsl-remote-4090`）。
