# Arithmetic Intensity — Dominant Kernel

## Dominant Kernel Identified

**`conv3x3_int8_vectorized`** — a 3×3 INT8 convolution with fused ReLU,
accounting for **95.6%** of total execution time (2.275 s of 2.379 s across
15 profiled runs). This is the operation the accelerator will target.

## Layer Dimensions

| Parameter | Symbol | Value |
|-----------|--------|-------|
| Input height/width | H, W | 52 × 52 |
| Input channels | C_in | 64 |
| Output channels | C_out | 128 |
| Kernel size | K_h × K_w | 3 × 3 |
| Padding | P | 1 (same) |
| Stride | S | 1 |
| Data type | — | INT8 (1 byte) |

## FLOP Count (Analytical)

Each output element requires a dot product across the full 3 × 3 × C_in kernel
window. Each dot-product element is one multiply + one accumulate = 2 operations.

```
MACs per output element = K_h × K_w × C_in
                        = 3 × 3 × 64
                        = 576

Total output elements   = H_out × W_out × C_out
                        = 52 × 52 × 128
                        = 346,112

Total MACs              = 576 × 346,112
                        = 199,360,512

Total FLOPs             = 2 × MACs
                        = 2 × 199,360,512
                        = 398,721,024  (≈ 399 MFLOP)
```

*(The ReLU adds 346,112 comparisons — negligible at <0.1% of total ops, so omitted.)*

## Bytes Transferred (No Reuse — All Operands from DRAM)

Assuming every unique byte of input, weight, and output data is loaded/stored
exactly once from DRAM (i.e., no on-chip buffering reduces traffic below the
total data footprint):

```
Input feature map  = H × W × C_in  × 1 byte  = 52 × 52 × 64  × 1 = 173,056 B
Weights            = K_h × K_w × C_in × C_out × 1 byte
                   = 3 × 3 × 64 × 128 × 1     = 73,728 B
Output feature map = H × W × C_out × 1 byte   = 52 × 52 × 128 × 1 = 346,112 B
─────────────────────────────────────────────────────────────────────
Total bytes        = 173,056 + 73,728 + 346,112 = 592,896 B  (≈ 579 KB)
```

## Arithmetic Intensity

```
AI = Total FLOPs / Total Bytes
   = 398,721,024 / 592,896
   ≈ 672.5 FLOP/byte
```

## Interpretation

An arithmetic intensity of **~673 FLOP/byte** is extremely high. This is
characteristic of convolution: each weight byte is reused across all spatial
positions (52 × 52 = 2,704 reuses), and each input byte is reused across all
output channels (128 reuses). The kernel is **deeply compute-bound** on any
platform where the ridge point is below ~673 — which includes essentially all
CPUs and most accelerators. This confirms that a design with more MAC units
will directly increase throughput, and that memory bandwidth is unlikely to be
the bottleneck.
