# Heilmeier Answers (Updated Post-Profiling)

## 1. What are you trying to do?

I want to build a dedicated hardware accelerator to perform the 3×3 INT8
convolution operation — the single most time-consuming step in YOLO-nano
object detection inference. Today this runs on general-purpose processors that
waste energy on capabilities my task doesn't need. My chip performs only this
one operation with a small array of fixed-function multiply-accumulate units,
so it can do it faster per watt. The goal is a module that could sit inside a
small camera or sensor and run the convolution layers of YOLO-nano without
needing a full GPU.

## 2. How is it done today, and what are the limits of current practice?

Today, YOLO-nano runs on either GPUs (fast but power-hungry) or CPUs
(available everywhere but slow for this workload). **Profiling confirms that
the 3×3 convolution kernel accounts for 95.6% of total layer execution time**
(2.275 s out of 2.379 s across 15 runs of a representative 52×52×64→128
layer). The kernel's arithmetic intensity is ~673 FLOP/byte, making it deeply
compute-bound on an M1 Pro CPU (ridge point ≈ 1.0). This means the CPU's peak
FLOP rate — not memory bandwidth — is the bottleneck. An M1 Pro peaks at
~200 GFLOP/s (FP32 NEON), yielding ~158 ms per layer inference in our profiled
implementation. Edge devices with lower compute budgets fare even worse.
Existing edge AI chips solve this but are fixed products that cannot be
customized for a specific model's layer shapes or deployment constraints.

## 3. What is new in your approach and why do you think it will be successful?

I am designing a custom INT8 MAC array (128 units at 250 MHz, 64 GOPS) tuned
to the dominant 3×3 convolution shape in YOLO-nano. **Roofline analysis
confirms this kernel is compute-bound on both the CPU baseline and the proposed
accelerator**, meaning throughput scales directly with the number of multipliers.
INT8 arithmetic reduces each multiplier's area by ~4× compared to FP32,
letting me pack more MACs into a given silicon or FPGA budget. The architecture
streams feature-map data through line buffers via AXI4-Stream and holds weights
in on-chip SRAM, achieving ~32 GB/s on-chip bandwidth — far more than the
~91 MB/s required at target throughput, leaving 4× headroom on the interface
so the design will not become I/O-bound. Profiling changed my confidence in one
key detail: the arithmetic intensity is even higher than I initially expected
(673 vs. a rough estimate of ~100–200), which strengthens the case for a
compute-focused design. More MACs will deliver near-linear speedup.
