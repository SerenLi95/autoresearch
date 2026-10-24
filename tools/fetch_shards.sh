#!/bin/sh
# Pre-fetch the shards prepare.py needs (0..9 + pinned val 6542) via hf-mirror;
# prepare.py skips files that already exist, so it then only trains the tokenizer.
# usage: sh fetch_shards.sh          (fetch all, 6 in parallel)
#        sh fetch_shards.sh <index>  (fetch one)
D=/root/rivermind-data/cache/autoresearch/data
URL=https://hf-mirror.com/datasets/karpathy/climbmix-400b-shuffle/resolve/main
if [ -z "$1" ]; then
  mkdir -p $D
  printf "%s\n" 0 1 2 3 4 5 6 7 8 9 6542 | xargs -P 6 -n 1 sh "$0"
  echo "FETCH_DONE $(ls $D/*.parquet 2>/dev/null | wc -l) shards"
  exit 0
fi
f=$(printf "shard_%05d.parquet" "$1")
[ -e $D/$f ] && { echo "exists $f"; exit 0; }
for a in 1 2 3 4 5; do
  curl -sS -L --connect-timeout 20 --speed-limit 50000 --speed-time 60 -o $D/$f.tmp $URL/$f \
    && [ "$(head -c4 $D/$f.tmp)" = PAR1 ] && [ "$(tail -c4 $D/$f.tmp)" = PAR1 ] \
    && mv $D/$f.tmp $D/$f && { echo "ok $f $(stat -c%s $D/$f)"; exit 0; }
  echo "retry $a $f"; rm -f $D/$f.tmp; sleep $((a * 5))
done
echo "FAILED $f"
