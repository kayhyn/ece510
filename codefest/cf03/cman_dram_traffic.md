DRAM Traffic: 32x32 FP32 MatMul, T=8

Setup: A, B, C are 32x32 FP32 (4 bytes per element).

1. Naive triple loop (ijk). For each C[i][j], the inner loop touches A[i][k] and B[k][j] for k=0..31, so 32 accesses to A and 32 to B per output. Every B[k][j] also gets pulled in by every row i, so each B element is read 32 times total. Across all N^2 outputs that's N^3 = 32,768 accesses to A and the same to B. With no reuse, DRAM traffic is 2 * N^3 * 4 = 262,144 bytes (256 KB).

2. Tiled loop with T=8. There are N/T = 4 tiles per dimension, 16 tiles per matrix, 256 bytes each. Each tile is loaded once and reused T times before moving on. That's 16 tile loads for A and 16 for B, so 2 * (N/T)^2 * T^2 * 4 = 8,192 bytes (8 KB). Same as 2 * N^2 * 4, which makes sense since every element ships from DRAM exactly once.

3. Ratio naive / tiled = N^3 / N^2 = N = 32. The naive version refetches each element N times; tiling with full reuse drops it to once.

4. Execution time. Work is 2 * N^3 = 65,536 FLOPs, compute time ~6.6 ns at 10 TFLOPS. Ridge point is 10 TFLOPS / 320 GB/s = 31.25 FLOPs/byte.
   - Naive: 262,144 / 320e9 = ~819 ns. Arithmetic intensity 0.25 FLOPs/B, deeply memory-bound. Bottleneck: memory.
   - Tiled: 8,192 / 320e9 = ~25.6 ns. Intensity 8 FLOPs/B, still below the ridge so still memory-bound, just 32x faster. Would need a bigger N to cross over to compute-bound.

Summary: DRAM traffic 256 KB vs 8 KB, runtime ~819 ns vs ~25.6 ns, both memory-bound, 32x improvement across the board.
