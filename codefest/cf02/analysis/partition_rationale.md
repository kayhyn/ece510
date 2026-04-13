# HW/SW Partition Rationale

## (a) Kernel to Accelerate and Roofline Justification

The 3×3 INT8 convolution kernel is the clear acceleration target. Profiling
shows it consumes **95.6%** of total inference time for the representative
YOLO-nano layer (52×52×64 → 128 output channels). Its arithmetic intensity of
**~673 FLOP/byte** places it far to the right of both the CPU ridge point
(1.0 FLOP/B) and the accelerator ridge point (2.0 FLOP/B) on the roofline,
confirming it is deeply **compute-bound** on both platforms. This means
every additional MAC unit translates directly into higher throughput — exactly
the scenario where a dedicated hardware array outperforms a general-purpose
core per watt and per area.

## (b) Software Baseline

The host CPU will continue to handle all non-convolutional YOLO-nano
operations: batch normalization, activation functions beyond the fused ReLU,
skip connections, detection-head post-processing (anchor decoding, NMS), and
model orchestration (layer scheduling, memory management, I/O). Together these
account for under 5% of compute time and are control-heavy or irregular, making
them poor hardware-acceleration candidates.

## (c) Required Interface Bandwidth

At the target throughput of 64 GOPS, the accelerator processes one conv layer
in approximately 399 MFLOP / 64 GOPS ≈ **6.2 ms**. Total data movement per
invocation is ~579 KB (input + weights + output). The required interface
bandwidth is therefore 579 KB / 6.2 ms ≈ **91 MB/s**. A single AXI4-Stream
link at 32 bits × 100 MHz delivers 400 MB/s — more than 4× headroom. The
accelerator will not be interface-bound.

## (d) Compute-Bound vs. Memory-Bound

On the laptop CPU, the kernel is **compute-bound**: its AI of 673 far exceeds
the CPU ridge point of 2.3, so throughput is capped by the CPU's peak FLOP rate
rather than by DRAM bandwidth. The custom accelerator preserves this property —
its ridge point of 2.0 FLOP/B is still far below 673, so the design remains
compute-bound. This is intentional: it means scaling up the MAC array (e.g.,
from 128 to 256 units) will yield a near-linear speedup without requiring a
proportional increase in memory bandwidth.
