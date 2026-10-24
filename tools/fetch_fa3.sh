#!/bin/sh
# Fetch the FA3 kernel .so into the HF hub cache with parallel curl ranges (hub's own
# xet download stalls behind hf-mirror). Reuses any partial .incomplete prefix, verifies
# sha256 against the LFS oid, then installs it as blobs/<oid> so get_kernel skips it.
. "$(cd "$(dirname "$0")" && pwd)/env.sh"
OID=97eb502bfc96def59bb9d164893e29fd303c0789992bf69371f76bcf8d74e0e0
SIZE=804184120
URL=https://hf-mirror.com/kernels-community/flash-attn3/resolve/main/build/torch211-cxx11-cu128-x86_64-linux/_flash_attn3_cuda_373a45c.abi3.so
B=$HF_HOME/hub/models--kernels-community--flash-attn3/blobs
W=$HF_HOME/fa3_parts; mkdir -p $W
[ -f $B/$OID ] && { echo "already installed"; exit 0; }
START=0; [ -f $B/$OID.incomplete ] && START=$(stat -c%s $B/$OID.incomplete)
N=8; STEP=$(( (SIZE - START + N - 1) / N ))
i=0
while [ $i -lt $N ]; do
  s=$((START + i * STEP)); e=$((s + STEP - 1)); [ $e -ge $SIZE ] && e=$((SIZE - 1))
  ( for a in 1 2 3 4 5 6 7 8 9 10; do
      have=$(stat -c%s $W/p$i 2>/dev/null || echo 0); want=$((e - s + 1))
      [ $have -ge $want ] && break
      curl -sS -L --connect-timeout 20 --speed-limit 20000 --speed-time 60 -r $((s + have))-$e "$URL" >> $W/p$i || sleep 5
    done; echo "part $i $(stat -c%s $W/p$i)/$((e - s + 1))" ) &
  i=$((i + 1))
done
wait
{ [ $START -gt 0 ] && cat $B/$OID.incomplete; i=0; while [ $i -lt $N ]; do cat $W/p$i; i=$((i + 1)); done; } > $W/full
GOT=$(sha256sum $W/full | cut -d" " -f1)
echo "size $(stat -c%s $W/full)/$SIZE sha256 $GOT"
if [ "$GOT" = "$OID" ]; then mv $W/full $B/$OID && rm -rf $B/$OID.incomplete $W && echo "FA3_OK installed"; else echo "FA3_BAD checksum mismatch"; fi
