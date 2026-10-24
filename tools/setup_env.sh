#!/bin/sh
# One-time environment setup on a GPU box whose base image already ships PyTorch + CUDA.
# Builds .venv on the system Python with --system-site-packages and installs every locked
# dependency EXCEPT torch/triton/nvidia-* so the preinstalled torch is reused (no GPU wheel
# downloads). Idempotent: safe to re-run; also links the dataset cache onto the data disk.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/env.sh"
cd "$HERE/.."
# prepare.py hard-codes ~/.cache/autoresearch; point it at the data disk
if [ ! -L "$HOME/.cache/autoresearch" ]; then
  [ -e "$HOME/.cache/autoresearch" ] && { echo "~/.cache/autoresearch exists and is not a symlink; move it first"; exit 1; }
  mkdir -p "$HOME/.cache" && ln -s "$XDG_CACHE_HOME/autoresearch" "$HOME/.cache/autoresearch"
fi
[ -x .venv/bin/python ] || uv venv -q --python /usr/bin/python3 --system-site-packages .venv
SKIP=$(grep -oE '^name = "(torch|triton|nvidia-[a-z0-9-]+)"' uv.lock | cut -d'"' -f2 | sed 's/^/--no-install-package /' | tr '\n' ' ')
uv sync --frozen $SKIP
.venv/bin/python -c "import torch; print('torch', torch.__version__, 'from', torch.__file__, 'cuda', torch.cuda.is_available())"
