# Interface Selection

## Chosen Interface

**AXI4-Stream**

## Host Platform

**FPGA SoC** (e.g., Xilinx Zynq UltraScale+ or similar) — the ARM host
processor on the SoC handles model orchestration, non-conv layers, and I/O,
while the programmable logic fabric contains the INT8 MAC-array accelerator.
AXI4-Stream is the native streaming interface on these platforms.

## Bandwidth Requirement Calculation

The accelerator targets 64 GOPS (128 INT8 MACs × 2 ops/MAC × 250 MHz).
At this throughput, one convolution layer (399 MFLOP) completes in:

```
Execution time = 399 × 10⁶ OPs / 64 × 10⁹ OPs/s = 6.2 ms
```

Total data transferred per layer invocation (all operands, no reuse across
the interface):

```
Input feature map  = 52 × 52 × 64  × 1 B = 173,056 B
Weights            = 3 × 3 × 64 × 128 × 1 B =  73,728 B
Output feature map = 52 × 52 × 128 × 1 B = 346,112 B
────────────────────────────────────────────────
Total              = 592,896 B ≈ 579 KB
```

Required interface bandwidth:

```
BW_required = 579 KB / 6.2 ms = 93.4 MB/s ≈ 0.091 GB/s
```

## Interface Rated Bandwidth vs. Required Bandwidth

A single AXI4-Stream link configured at **32 bits × 100 MHz** provides:

```
BW_rated = 4 B × 100 × 10⁶ Hz = 400 MB/s = 0.4 GB/s
```

| Metric            | Value      |
|-------------------|------------|
| Required BW       | 93.4 MB/s  |
| AXI4-Stream rated | 400 MB/s   |
| Headroom          | 4.3×       |

The rated bandwidth exceeds the requirement by more than 4×. **The
accelerator is not interface-bound.** On the roofline, the interface does
not introduce a new bottleneck — the design remains compute-bound at an
arithmetic intensity of 673 FLOP/byte, far above both the CPU ridge point
(1.0 FLOP/B) and the accelerator ridge point (2.0 FLOP/B).

Even if the clock is reduced to 50 MHz (200 MB/s), the interface still
provides 2× headroom, leaving margin for control overhead and
non-contiguous transfers.
