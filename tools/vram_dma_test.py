"""VRAM integrity test using only the CUDA driver API (no PyTorch, no kernels).

Data path: pinned host buffer -> cuMemcpyHtoD (DMA) -> VRAM -> wait -> cuMemcpyDtoH (DMA) -> compare.
Each pass reads every chunk twice to separate stored corruption (same word wrong on both
reads) from transient read errors (differs between reads).

usage: python vram_dma_test.py <reserve_gib> <wait_s>[,<wait_s>...] <label>
"""
import ctypes, os, sys, time, collections
import numpy as np

RESERVE_GIB = float(sys.argv[1])
WAITS = [float(w) for w in sys.argv[2].split(",")]
LABEL = sys.argv[3]
CHUNK = 256 * 2**20  # bytes
WORDS = CHUNK // 4
MAX_DETAIL = 200_000  # cap per-chunk words kept for bit analysis

cu = ctypes.CDLL("libcuda.so.1")
def ck(r, what):
    if r != 0:
        raise RuntimeError(f"{what} failed with CUresult {r}")
ck(cu.cuInit(0), "cuInit")
dev = ctypes.c_int(); ck(cu.cuDeviceGet(ctypes.byref(dev), 0), "cuDeviceGet")
ctx = ctypes.c_void_p(); ck(cu.cuDevicePrimaryCtxRetain(ctypes.byref(ctx), dev), "ctxRetain")
ck(cu.cuCtxSetCurrent(ctx), "cuCtxSetCurrent")

def pinned():
    h = ctypes.c_void_p(); ck(cu.cuMemAllocHost_v2(ctypes.byref(h), ctypes.c_size_t(CHUNK)), "cuMemAllocHost")
    return np.ctypeslib.as_array(ctypes.cast(h, ctypes.POINTER(ctypes.c_uint32)), shape=(WORDS,))
exp, recv = pinned(), pinned()
base = np.arange(WORDS, dtype=np.uint32)

# optional untested placeholder allocated first (controlled-location experiment)
SKIP_GIB = float(os.environ.get("SKIP_GIB", "0"))
if SKIP_GIB:
    hole = ctypes.c_uint64(); ck(cu.cuMemAlloc_v2(ctypes.byref(hole), ctypes.c_size_t(int(SKIP_GIB * 2**30))), "placeholder alloc")
    print(f"[{LABEL}] holding {SKIP_GIB} GiB untested placeholder allocated first", flush=True)
free, total = ctypes.c_size_t(), ctypes.c_size_t()
ck(cu.cuMemGetInfo_v2(ctypes.byref(free), ctypes.byref(total)), "cuMemGetInfo")
n_chunks = int((free.value - RESERVE_GIB * 2**30) // CHUNK)
ptrs = []
for _ in range(n_chunks):
    p = ctypes.c_uint64(); ck(cu.cuMemAlloc_v2(ctypes.byref(p), ctypes.c_size_t(CHUNK)), "cuMemAlloc")
    ptrs.append(p.value)
print(f"[{LABEL}] free {free.value/2**30:.2f} GiB / total {total.value/2**30:.2f} GiB; "
      f"testing {n_chunks} x 256 MiB = {n_chunks*CHUNK/2**30:.2f} GiB", flush=True)

def h2d(dptr, arr): ck(cu.cuMemcpyHtoD_v2(ctypes.c_uint64(dptr), arr.ctypes.data_as(ctypes.c_void_p), ctypes.c_size_t(CHUNK)), "HtoD")
def d2h(arr, dptr): ck(cu.cuMemcpyDtoH_v2(arr.ctypes.data_as(ctypes.c_void_p), ctypes.c_uint64(dptr), ctypes.c_size_t(CHUNK)), "DtoH")

def fill_expected(pattern, ci):
    if pattern == "addr":  # every word distinct and position-dependent
        np.add(base, np.uint32((ci * WORDS) & 0xFFFFFFFF), out=exp)
        np.multiply(exp, np.uint32(2654435761), out=exp)
        np.bitwise_xor(exp, np.uint32(0x5A5A0F0F), out=exp)
    else:
        exp.fill(pattern)

def bits(a):
    # (n, 32) matrix of bit values, column b = bit b
    return np.unpackbits(np.ascontiguousarray(a, dtype=np.uint32).view(np.uint8), bitorder="little").reshape(-1, 32)

PATTERNS = [0x00000000, 0xFFFFFFFF, 0x55555555, 0xAAAAAAAA, "addr"]
if os.environ.get("PATTERNS"):
    PATTERNS = [p if p == "addr" else int(p, 16) for p in os.environ["PATTERNS"].split(",")]
location_hits = collections.Counter()   # (chunk, word) -> passes with a stored error
region_hits = collections.Counter()     # (chunk, MiB offset) -> stored errors
chunk_hits = collections.Counter()
grand = collections.Counter()

for wait in WAITS:
    for pat in PATTERNS:
        pname = pat if isinstance(pat, str) else f"0x{pat:08X}"
        t0 = time.time()
        for ci, p in enumerate(ptrs):
            fill_expected(pat, ci)
            h2d(p, exp)
        ck(cu.cuCtxSynchronize(), "sync")
        time.sleep(wait)
        bad_by_read = [{}, {}]
        detail = {}
        for ci, p in enumerate(ptrs):
            fill_expected(pat, ci)
            for rd in (0, 1):
                d2h(recv, p)
                idx = np.flatnonzero(recv != exp)
                if idx.size:
                    bad_by_read[rd][ci] = idx.size
                    if rd == 0:
                        keep = idx[:MAX_DETAIL]
                        detail[ci] = (keep, exp[keep].copy(), recv[keep].copy())
                    else:
                        detail[ci] = detail.get(ci, (np.empty(0, np.int64),) * 3) + (idx,)
        r1 = sum(bad_by_read[0].values()); r2 = sum(bad_by_read[1].values())
        persistent = 0; set_bits = cleared_bits = multi = 0; bitpos = collections.Counter()
        for ci, d in detail.items():
            idx, e, g = d[:3]
            idx2 = d[3] if len(d) > 3 else np.empty(0, np.int64)
            both = np.intersect1d(idx, idx2)
            persistent += both.size
            location_hits.update((ci, w) for w in both.tolist())
            region_hits.update((ci, w * 4 // 2**20) for w in both.tolist())
            chunk_hits[ci] += both.size
            if idx.size:
                set_bits += int(bits(g & ~e).sum()); cleared_bits += int(bits(e & ~g).sum())
                xb = bits(g ^ e)
                multi += int((xb.sum(1) > 1).sum())
                bitpos.update({b: int(n) for b, n in enumerate(xb.sum(0)) if n})
        grand["read1"] += r1; grand["read2"] += r2; grand["persistent"] += persistent
        print(f"[{LABEL}] wait={wait:>3.0f}s pattern={pname:<10} read1_err={r1:<7} read2_err={r2:<7} "
              f"in_both_reads={persistent:<7} flips 0->1={set_bits} 1->0={cleared_bits} "
              f"multi-bit-words={multi} chunks={dict(sorted(bad_by_read[0].items()))} "
              f"top_bits={bitpos.most_common(4)} ({time.time()-t0:.0f}s)", flush=True)

recurring = sum(1 for v in location_hits.values() if v > 1)
print(f"[{LABEL}] TOTAL read1={grand['read1']} read2={grand['read2']} in_both_reads={grand['persistent']}; "
      f"distinct bad words={len(location_hits)}, same word bad in >1 pass={recurring}", flush=True)
print(f"[{LABEL}] errors per chunk: {dict(sorted(chunk_hits.items()))}", flush=True)
print(f"[{LABEL}] top 1MiB regions (chunk, MiB offset): {region_hits.most_common(8)}", flush=True)
for p in ptrs: cu.cuMemFree_v2(ctypes.c_uint64(p))
