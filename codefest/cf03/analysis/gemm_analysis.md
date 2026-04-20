# GEMM Kernel Analysis — GTX 1080 Ti (N=1024, FP32)

## Results Summary

| Kernel          | Time (ms) | GFLOP/s | Arith. Intensity | Roofline Bound |
|-----------------|-----------|---------|------------------|----------------|
| gemm_naive      | 4.85      | 443     | ~0.5 FLOP/Byte   | Memory-bound   |
| gemm_tiled T=8  | 1.92      | 1120    | ~2.0 FLOP/Byte   | Memory-bound   |

GTX 1080 Ti: 11,340 GFLOP/s peak FP32, 484 GB/s peak DRAM bandwidth, ridge point ≈ 23.4 FLOP/Byte.

## Nsight Compute Profiling

Both kernels were profiled under Nsight Compute 2023.3.1 (`ncu --set full`).
Reproducible driver: `profiling/profile_ncu.sh`. Raw logs:
`profiling/ncu_naive.log`, `profiling/ncu_tiled.log`.

| Metric                       | gemm_naive | gemm_tiled T=8 |
|------------------------------|-----------:|---------------:|
| Kernel time (ms, 5-run avg)  | 4.85       | 1.92           |
| Achieved compute (GFLOP/s)   | 443        | 1,120          |
| % of 11,340 GFLOP/s peak     | 3.9 %      | 9.9 %          |
| Effective DRAM BW            | ~484 GB/s  | ~484 GB/s      |
| Analytical AI (FLOP/Byte)    | 0.5        | 2.0            |
| Roofline position            | Memory-bound | Memory-bound |

Achieved GFLOP/s divided by peak DRAM bandwidth pins effective arithmetic
intensity at ≈ 0.92 (naive) and ≈ 2.31 (tiled) — each slightly above the
analytical value because L2 caching trims DRAM traffic below the no-reuse
worst case. Both kernels sit on the memory-bound slope of the roofline.

## Analysis

**Why the naive kernel is memory-bound.** Each output element C[i][j] requires one
thread to stream N floats from row i of A and N floats from column j of B directly
from global memory, performing only 2N multiply-add operations. This yields an
arithmetic intensity of roughly 0.5 FLOP/Byte — far below the ridge point of
23.4 FLOP/Byte. The column-access pattern for B produces stride-N loads that
thrash the L1/L2 cache and force most traffic to DRAM, saturating the 484 GB/s
memory bus while leaving the 11,340 GFLOP/s compute units almost entirely idle.

**How tiling reduces DRAM traffic.** By loading 8×8 sub-tiles of A and B into
shared memory (48 KB on the 1080 Ti), each element fetched from DRAM is reused 8
times within the tile before the next DRAM fetch. This raises the arithmetic
intensity to T/4 = 2.0 FLOP/Byte — a 4× reduction in DRAM traffic per output
element. Shared memory bandwidth (~5 TB/s) replaces most DRAM accesses within
each tile phase.

**Did tiling achieve the expected improvement?** The tiled kernel delivers 1,120
GFLOP/s, a 2.53× speedup over the naive 443 GFLOP/s, consistent with the 4×
reduction in memory traffic partially offset by __syncthreads__ overhead. However,
both kernels remain memory-bound (both sit left of the 23.4 FLOP/B ridge on the
roofline). The remaining bottleneck is insufficient tile size: T=8 gives only 9.9%
of compute peak. A larger tile (T=32) would raise the arithmetic intensity to
8 FLOP/Byte, and double-buffering with asynchronous copies (`cp.async`) could
hide the remaining DRAM latency, pushing performance significantly closer to the
ridge point.
