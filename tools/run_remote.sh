#!/bin/sh
# Local-side driver for one experiment: sync the current branch/HEAD to the GPU box,
# run `uv run train.py > run.log` there (nohup, survives ssh drops), wait, print the summary.
# usage: sh tools/run_remote.sh          (HOST defaults to ZCY-4090; git remote `zcy` must point at it)
set -e
HOST=${HOST:-ZCY-4090}
BR=$(git branch --show-current)
REV=$(git rev-parse HEAD)
DEADLINE=${DEADLINE:-720}   # seconds; program.md: >10 min of training wall time = failure

git push -q -f zcy "$BR"
ssh -n "$HOST" "cd /root/autoresearch && git checkout -q $BR && git reset -q --hard $REV && rm -f run.log && \
  nohup sh -c 'uv run train.py > run.log 2>&1; echo EXIT=\$? >> run.log' </dev/null >/dev/null 2>&1 &"
echo "started $(git rev-parse --short HEAD) on $HOST:$BR"

t=0
until ssh -n "$HOST" 'grep -q "^EXIT=" /root/autoresearch/run.log' 2>/dev/null; do
  sleep 20; t=$((t + 20))
  if [ $t -ge $DEADLINE ]; then
    ssh -n "$HOST" 'pkill -f "[t]rain.py"; echo EXIT=timeout >> /root/autoresearch/run.log' || true
    break
  fi
done
ssh -n "$HOST" 'cd /root/autoresearch && grep "^val_bpb:\|^peak_vram_mb:\|^num_steps:\|^training_seconds:\|^EXIT=" run.log; grep -q "^val_bpb:" run.log || tr "\r" "\n" < run.log | tail -n 30'
