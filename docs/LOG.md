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

## L9 · 2026-10-25 · ZCY-4090：baseline 训练跑通

- **做法**：FA3 kernel 通过 sha256 校验后，运行 `uv run train.py > run.log`（`tools/train_after_fa3.sh`），代码版本 `6e20959`（`train.py` 与 `8156015` 相同）。
- **结果**：`TRAIN_EXIT=0`，日志里 NaN/FAIL/Traceback 共 **0** 次。

  | 指标 | 值 |
  |---|---|
  | **val_bpb** | **1.122878** |
  | training_seconds / total_seconds | 300.8 / 384.3 |
  | peak_vram_mb | 11701.0（≈11.4 GB / 24 GB） |
  | num_steps | 260（每步约 1.21 s，约 43.3 万 tok/s） |
  | total_tokens_M | 136.3 |
  | num_params_M / depth | 50.3 / 8 |
  | mfu_percent | 10.53（按 H100 峰值算，只能做相对参考） |

- **loss 曲线**（平滑后）：step 0 = 9.01 → 39 = 5.09 → 79 = 4.08 → 119 = 3.63 → 159 = 3.41 → 199 = 3.27 → 239 = 3.19 → 259 = 3.13。曲线单调下降；`lrm` 从 60% 进度开始按 warmdown 降到 0，符合配置（`WARMDOWN_RATIO=0.5`）。
- **证据**：远程 `/root/autoresearch/run.log`；baseline 已经记入远程 `results.tsv`（不进 git，`program.md` 的规定）。
- **对比**：`program.md` 里的 H100 示例输出是 val_bpb 0.9979、953 步。4090 在 5 分钟内只能跑 260 步，所以 bpb 偏高，符合预期，不是 bug。
- **附注**：训练后系统盘从 410 MB 涨到约 910 MB，经排查，其中 475 MB 是用户的 Cursor 远程服务端（`/root/.cursor-server`），约 20 MB 是 venv 的字节码；训练没有往系统盘写大文件。

## L10 · 2026-10-25 · 开始自主实验循环（教学用）

- **目标**（用户明确）：这是教学项目，目的是学会用 AI 工具驱动 AutoResearch 的工作流程，不追求结果有多好。所以只跑约 1 小时、约 8 个实验，覆盖“保留 / 丢弃 / 崩溃”三种情况，最后写流程复盘。
- **分支**：`autoresearch/oct25-4090d`（`program.md` 规定格式 `autoresearch/<tag>`，tag 用日期，后缀标明硬件）。没有从 `master` 拉，因为 `master` 缺少 batch size 修复，在 24 GB 卡上会 OOM；改为从 `repro/wsl-remote-4090` 拉出。
- **流程**：本地改 `train.py` → commit → `sh tools/run_remote.sh`（推送到远程并运行，超过 12 分钟按失败处理）→ 结果追加到远程 `results.tsv` → 变好则保留（推送到 GitHub），否则 `git reset --hard HEAD~1`。
- **初始判断**：5 分钟只能跑 260 步、1.36 亿 token，模型有 5000 万参数（每个参数约 2.7 个 token），训练量严重不足。所以优先尝试“同样时间里多走几步”的方向：减小 `TOTAL_BATCH_SIZE`、减小模型、提高单步吞吐。
- **实验 0**：baseline 原样重跑一次，用来测量同一配置两次运行之间的噪声，作为后面判断保留还是丢弃的阈值。

## L11 · 2026-10-25 · 实验循环结果与复盘（约 1 小时，8 个实验）

- **结果**：最好成绩是 commit `d01c2b3`，**val_bpb 1.099618**，比 baseline 1.122878 低 **0.0233**（约为种子噪声的 20 倍）。分支 `autoresearch/oct25-4090d` 当前指向它。
- **完整记录**（远程 `results.tsv` 的副本；`results.tsv` 按 `program.md` 不进 git，另有本地备份 `results/oct25-4090d/`，已用 sha256 核对）：

  | # | commit | val_bpb | 显存 GB | 状态 | 改动 | 步数 |
  |---|---|---|---|---|---|---|
  | — | `6e20959` | 1.122878 | 11.4 | keep | baseline | 260 |
  | 0 | `6eea852` | 1.122641 | 11.4 | keep | baseline 重跑（同种子噪声 0.00024） | 260 |
  | 1 | `8b0bb81` | **1.108940** | 11.4 | **keep** | `TOTAL_BATCH_SIZE` 2^19 → 2^18 | 506 |
  | 2 | `2510e1d` | 1.119285 | 11.4 | discard | `TOTAL_BATCH_SIZE` 2^17（batch 太小，梯度噪声大） | 994 |
  | 3 | `ae7d70c` | 1.128049 | 22.3 | discard | `DEVICE_BATCH_SIZE` 64（没有提速，bpb 反而变差） | 511 |
  | 4 | `cf07648` | 1.107869 | 11.4 | discard | 种子 43（只做测量：种子噪声约 0.0011） | 506 |
  | 5 | `936d1be` | **1.101800** | 6.9 | **keep** | `DEPTH` 8 → 6（参数 2630 万） | 937 |
  | 6 | `c9d041b` | 1.100160 | 6.9 | discard | `WARMDOWN_RATIO` 0.3（−0.0016，在噪声范围内，无法下结论） | 937 |
  | 7 | `d01c2b3` | **1.099618** | 6.9 | **keep** | `MATRIX_LR` 0.04 → 0.06（−0.0022，刚过阈值，属于边缘改进） | 936 |

- **复盘：这一轮学到的东西**
  1. **先找瓶颈，再动手。** 读完代码后先算了一笔账：5 分钟只能看到 1.36 亿 token，对 5000 万参数来说太少。真正有效的两个改动（更小的 batch、更小的模型）都来自这个判断，不是随机试出来的。
  2. **同一方向走过头会变差。** batch 从 2^19 减到 2^18 是改进，再减到 2^17 就退化了。超参数通常存在一个最佳点，要试到“变差”为止，才知道最佳点在哪。
  3. **“看起来应该更快”不等于更快。** `DEVICE_BATCH_SIZE` 64 理论上能减少梯度累积开销，实际步数几乎没变（511 对 506）：batch 32 时 GPU 已经跑满了。系统层面的猜想也要靠实验验证。
  4. **噪声要用对方法测。** 同种子重跑只测出 GPU 的非确定性（0.00024）；换种子才反映真实波动（约 0.0011），大了 4 倍多。判断阈值据此定为 0.002，实验 6 因此被正确地判为“不确定”。
  5. **纪律比单个数字重要。** 实验 6 数字上变好了，但因为在噪声范围内被丢弃；实验 7 刚好过阈值，保留了，但标为边缘改进。如果要确认实验 6、7 的效果，正确的做法是多跑几个种子取平均。
- **如果继续跑，下一步可以试**：`DEPTH` 4/5（继续缩小模型，验证是否也会“走过头”）；用 3 个种子重新验证实验 6、7；在小模型上重新调 `TOTAL_BATCH_SIZE`（模型变了，最佳 batch 可能也跟着变）。
