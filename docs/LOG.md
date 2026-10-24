# 工作日志（LOG）

> **只追加，不修改历史条目。** 写错了就在后面的新条目里更正，并注明更正的是哪一条。
> 当前状态和下一步看 [`STATUS.md`](STATUS.md)；本文件记录“发生了什么、为什么这么做、证据在哪”。
>
> 条目格式：**目的 → 做法 → 结果 → 证据 → 决策/结论**。时间以远程服务器时间（CST）为准。

---

## L1 · 2026-10-24 · bitahub-4090：首次运行 OOM

- **目的**：在远程 RTX 4090（24 GB）上跑通 `train.py`。
- **现象**：前向传播时 `torch.OutOfMemoryError`，申请的是一个 `(262144, 2048)` bf16 张量，262144 = `DEVICE_BATCH_SIZE`(128) × `MAX_SEQ_LEN`(2048)。
- **原因**：`DEVICE_BATCH_SIZE=128` 是按 80 GB H100 调的（上游参考峰值约 45 GB）。
- **修复**：`DEVICE_BATCH_SIZE` 128 → 32。`TOTAL_BATCH_SIZE` 保持 2^19 不变，梯度累积步数由 2 变为 8，所以等效 batch 和优化过程不变。
- **证据**：commit `8156015 fix(train): reduce DEVICE_BATCH_SIZE to 32 to fit 24GB GPUs`。
- **附注**：非交互 SSH 下找不到 `uv`（它在 `/opt/conda/bin`），需要手动补 `PATH`。`NO_COMPILE=1` 这个环境变量 `train.py` 根本没有读取，设了等于没设。

## L2 · 2026-10-24 · bitahub-4090：OOM 修好后出现 NaN

- **现象**：step 0 的 loss 为 9.01（≈ ln 8192，正常），随后 loss 变成 NaN，触发 `FAIL` 退出。
- **排查过程**（每一步都排除了一类原因）：
  1. 与上游 `master` 做 diff：除了 L1 的那一行，`train.py` 和上游完全一致 → 不是代码改动引起的。
  2. 插桩：NaN 出现在**前向传播**中，发生在随机的 micro-step，期间没有任何 optimizer step。同一个 batch 用 eager 模式重跑，loss 正常（9.01）。
  3. 关掉 `torch.compile` 后仍然 NaN → 不是编译器的问题。
  4. 用 forward hook 定位：第一个 NaN 出现在 FA3 attention 的输出上。但单独测试时 FA3 数值正确，而在训练规模的 batch 下，**FA3、FA2、PyTorch 自带的 SDPA 都会随机出 NaN** → 不是某个 kernel 的问题。
  5. 底层测试：在显卡内复制 1 GiB 数据，每次都有 13–138 个元素出错；同一个 bf16 matmul 跑 50 次，50 次结果都不同。
- **结论**：显存硬件故障。代码层面无法修复，当时停止了“修复→推送→重跑”循环。

## L3 · 2026-10-24 · BH-4090：换机后仍然 NaN，做严格复核

- **做法**：两端都强制对齐到 `origin/repro/wsl-remote-4090` 并清理（`git clean -fd`，**不带** `-x`，以保留 `.venv`）。新机器的 SSH host key 经用户同意后加入了 known_hosts。
- **现象**：显存复制测试有 0–26 个元素出错；训练同样在 step 0 之后 `FAIL`。
- **软件/环境排除**：没有其他租户占用 GPU（空闲时全局显存 1 MiB，利用率 0%）；没有 vGPU/MIG；显存频率是官方值 10501 MHz，功耗墙 450 W 为默认值，没有温度或功耗降频；驱动 580 + torch cu12.8 属于官方支持的组合。
- **严格复核**：自己写了 `tools/vram_dma_test.py`，只用 CUDA driver API（ctypes 直接调用），**不经过 PyTorch，也不跑任何 GPU kernel**，只用 DMA 写入、回读、比对：
  - 空闲状态 10 轮、约 22 GiB：共 5735 个错误字，**全部集中在一个约 12 MiB 的区域内**（分配起点之后约 682–693 MiB）。
  - 出过错的字一共 1201 个，其中 1074 个（89%）在不同测试图案下**反复出错**；两次读取结果一致，说明是存储内容本身被改了。
  - 写全 0 时只出现 0→1 翻转，写全 1 时只出现 1→0 翻转，并且总是同几个 bit 位（8/10/24/26）出错。
  - **对照实验**：先占住 1 GiB 不测，剩下 21 GiB 的错误数为 **0**；紧接着不占位再测，**1862** 个错误在同一位置重新出现。另外在另一个进程占用部分显存、GPU 满载（450 W，80 °C）时，错误数也是 0。
- **结论**：BH-4090 有约 12 MiB 的显存物理损坏，错误跟着物理地址走，与软件、负载、温度都无关。建议换卡。

## L4 · 2026-10-24 · ZCY-4090：新机器环境搭建

- **硬件验收**：`vram_dma_test.py` 测试 22 GiB、5 种图案，**0 错误**。
- **网络限制**：GitHub 和 huggingface.co 都超时。PyPI 可以通过清华镜像访问（`uv.lock` 本来就锁定的是这个镜像），HF 内容走 hf-mirror.com，速度约 1 MB/s。
- **拉代码**：远程连不上 GitHub，所以在本地对 `repro/wsl-remote-4090` 做 `git bundle`，用 scp 传过去再 clone。之后把 `origin` 改回 GitHub URL，并设置上游跟踪分支。
- **环境（决策 D3）**：基础镜像自带 **torch 2.11.0+cu128 / Python 3.12**，而 `uv.lock` 锁的是 torch **2.9.1**。按用户要求“不要重复下载 PyTorch”，做法是：`uv venv --system-site-packages` 加上 `uv sync --frozen --no-install-package torch/triton/nvidia-*`。结果是安装了 47 个普通包，venv 里没有 torch/triton/nvidia 的任何副本，`uv.lock` 也没有被修改。
  - 防坑：直接执行 `uv run` 会先自动 sync（会去装 2.9.1），还会按 `.python-version` 去下载 Python 3.10。所以在 `env.sh` 里设置了 `UV_NO_SYNC=1` 和 `UV_PYTHON=/usr/bin/python3`。
- **数据（决策 D5）**：`prepare.py` 写死了 `huggingface.co`（访问不了），而且它是只读文件，不能改。但它会跳过已经存在的分片，所以先用 `tools/fetch_shards.sh` 从 hf-mirror 按原文件名下好分片（每个文件首尾都校验 `PAR1` 魔数），再运行**未修改的** `uv run prepare.py`。
- **证据**：`/root/tools/prep.log`、`pipeline.log`（远程）。

## L5 · 2026-10-24 · 磁盘分工（决策 D4，用户中途多次调整后定稿）

- **约束**：系统盘 `/` 30 GB、**会随镜像保存**；数据盘 `/root/rivermind-data` 49 GB、速度快、可扩容，但**不会随镜像保存**。
- **过程**：用户先要求代码也放数据盘，随后改为让我自己判断，最后确认采用下面这套规范。
- **定稿**：
  - 系统盘：代码和 `.venv` 放在 `/root/autoresearch`（venv 依赖系统盘上的 Python 和 torch，必须和它们一起进镜像）；`~/.bashrc` 第一行加载 `env.sh`。
  - 数据盘：数据集、tokenizer、HF/uv/inductor/triton/CUDA 缓存全部放在 `/root/rivermind-data/cache`。
  - `prepare.py` 写死了 `~/.cache/autoresearch`，所以这个路径做成指向数据盘的软链接；`env.sh` 每次都会创建数据盘上的目录，保证新实例的空数据盘上软链接不会悬空。
- **结果**：系统盘占用约 410 MB，数据盘约 1.6 GB。

## L6 · 2026-10-25 · `prepare.py` 完成

- 11 个分片（训练 0–9，加上固定的验证分片 06542，约 1 GB）全部就绪。
- Tokenizer 训练耗时 48.6 s，vocab_size=8192，sanity check 通过，`PREP_EXIT=0`。

## L7 · 2026-10-25 · FA3 kernel 下载卡住

- **现象**：`train.py` 在 import 阶段调用 `get_kernel("kernels-community/flash-attn3")`，下载 767 MiB 的 `.so`（`torch211-cxx11-cu128` 版本）。`huggingface_hub` 默认走 Xet 通道，速度降到约 0.1 MB/s，最后变成 0。
- **做法**：停掉训练（`TRAIN_EXIT=143` 是我主动发的 SIGTERM），然后用 `tools/fetch_fa3.sh`：
  - 复用已经下载的前缀，剩余部分分 8 段并行 curl，速度约 4 MB/s；
  - 校验 **sha256 必须等于 LFS oid** `97eb502b…74e0e0`；
  - 放到 hub 缓存的 `blobs/<oid>`，这样 `get_kernel` 发现文件已存在就会跳过下载。
- **教训**：在 SSH 命令里用 `pkill -f "<模式>"` 会把这条 SSH 会话自己也杀掉，因为命令行里含有同样的字符串（这次会话里犯了两次）。要用 `[t]rain.py` 这种方括号写法，或者 `pgrep` 加 PID。

## L8 · 2026-10-25 · 三边同步机制

- **三边**：本地 WSL `/home/lxx/projects/autoresearch`、GitHub `origin`（SerenLi95/autoresearch）、远程 ZCY-4090 `/root/autoresearch`。
- **限制**：远程连不上 GitHub，所以由**本地做中转**。本地加了一个 git remote `zcy` = `ZCY-4090:/root/autoresearch`；远程设置 `receive.denyCurrentBranch=updateInstead`，本地推送时远程工作区会自动更新，如果远程有未提交的改动，推送会被拒绝，不会覆盖。
- **流程**：本地 commit → `git push origin` → `git push zcy` → 检查三边的 `rev-parse` 是否一致。
- `run.log` 加入 `.gitignore`（和 `results.tsv` 一样，结果文件不进 git，见 `program.md`）。
- 运维脚本从远程的 `/root/tools` 收进仓库的 `tools/`，随三边同步。
