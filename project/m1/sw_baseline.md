# Software Baseline Benchmark

## Platform and Configuration

| Item             | Value                                                      |
|------------------|------------------------------------------------------------|
| CPU              | Apple M1 Pro (8 performance + 2 efficiency cores)          |
| OS               | macOS (Darwin), ARM64                                      |
| Python version   | 3.12                                                       |
| NumPy version    | Latest (uses Apple Accelerate / NEON backend)              |
| Data type        | INT8 activations and weights, INT32 accumulation           |
| Batch size       | 1 (single-image inference)                                 |
| Layer dimensions | Input 52×52×64, Kernel 3×3×64×128, Output 52×52×128       |
| Convolution      | im2col + GEMM (vectorized NumPy), stride 1, same-padding  |

## Execution Time

Wall-clock timing over 15 runs of the dominant 3×3 INT8 convolution kernel
(`conv3x3_int8_vectorized`), measured with `time.perf_counter()`:

| Run | Time (ms) |
|-----|-----------|
| 1   | 164.1     |
| 2   | 164.5     |
| 3   | 155.6     |
| 4   | 164.3     |
| 5   | 171.8     |
| 6   | 161.3     |
| 7   | 163.0     |
| 8   | 151.0     |
| 9   | 149.0     |
| 10  | 150.5     |
| 11  | 160.7     |
| 12  | 163.8     |
| 13  | 144.6     |
| 14  | 160.9     |
| 15  | 150.6     |

**Median (15 runs): 160.9 ms**
Mean: 158.4 ms | Std: 7.4 ms

## Throughput

The convolution layer performs 398,721,024 FLOPs (see `ai_calculation.md`).

```
Throughput = 398,721,024 FLOPs / 0.1609 s ≈ 2.48 GFLOP/s
Layer inferences per second = 1 / 0.1609 s ≈ 6.2 layers/sec
```

For context, the M1 Pro CPU peaks at ~200 GFLOP/s (FP32 NEON). The NumPy
im2col path achieves only ~1.2% of peak, reflecting Python/NumPy overhead
and the INT8→INT32 cast pipeline rather than a hand-tuned BLAS kernel.

## Memory Usage

Estimated peak resident memory for one inference of this layer:

| Component                         | Size       |
|-----------------------------------|------------|
| Input feature map (INT8)          | 173 KB     |
| Padded input (INT8)               | 187 KB     |
| Weights (INT8)                    | 72 KB      |
| im2col patches matrix (INT32)     | 6,229 KB   |
| Weight matrix reshaped (INT32)    | 288 KB     |
| Output matrix (INT32 pre-clamp)   | 1,353 KB   |
| Output feature map (INT8)         | 338 KB     |
| **Working set subtotal**          | **8,640 KB (~8.4 MB)** |
| Python + NumPy runtime overhead   | ~35 MB     |
| **Estimated peak RSS**            | **~44 MB** |

The working set of ~8.4 MB fits comfortably in the M1 Pro's L2 cache
(shared 24 MB), so DRAM bandwidth is not the bottleneck during execution.
