# autoresearch environment: code + .venv on the system disk (saved with the image),
# datasets and all caches on the data disk (fast, not saved with the image).
# Source in every shell (setup_env.sh, ~/.bashrc). Paths assume the ZCY-4090 layout: /root/rivermind-data = data disk.
export XDG_CACHE_HOME=/root/rivermind-data/cache
export HF_HOME=/root/rivermind-data/cache/huggingface
export HF_ENDPOINT=https://hf-mirror.com
export TORCHINDUCTOR_CACHE_DIR=/root/rivermind-data/cache/torchinductor
export TRITON_CACHE_DIR=/root/rivermind-data/cache/triton
export CUDA_CACHE_PATH=/root/rivermind-data/cache/nv
# reuse the system torch: never let "uv run" re-sync (would install locked torch 2.9.1) or switch to .python-version 3.10
export UV_NO_SYNC=1
export UV_PYTHON=/usr/bin/python3
# a fresh data disk is empty: recreate the cache dirs so the ~/.cache/autoresearch symlink resolves
mkdir -p /root/rivermind-data/cache/autoresearch $HF_HOME $TORCHINDUCTOR_CACHE_DIR $TRITON_CACHE_DIR $CUDA_CACHE_PATH
