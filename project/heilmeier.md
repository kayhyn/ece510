# Heilmeier Answers (Updated After M4)

## 1. What are you trying to do?

I investigated a dedicated hardware accelerator for the 3×3 INT8
convolution operation — the single most time-consuming step in YOLO-nano
object detection inference. Today this runs on general-purpose processors that
also execute work outside the dense reduction. The final chiplet performs the
parallel INT8 products and INT32 reductions with 128 fixed-function MAC lanes;
a host remains responsible for sliding-window generation, padding, and adding
nine returned tile partials. It is a research prototype of the reduction
accelerator, not a complete YOLO-nano inference engine.

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

The final design is a custom 128-lane INT8 MAC array behind a narrow
AXI4-Stream interface. It uses output-stationary 64-element tiles and
carry-save accumulation, then serializes 128 channel partials for host
accumulation. The original proposal assumed full 576-entry on-chip weights,
line buffers, 250 MHz, and a non-interface-bound design. Those assumptions did
not survive implementation: inferred flip-flop storage forced 64-entry tiles,
the serializer became the main throughput limiter, and the full wrapper did
not close timing. The measured RTL schedule combined with a setup-limited
post-CTS frequency projection gives 9.335 GFLOP/s, but this is not a
timing-closed or end-to-end demonstrated speedup. The project is successful as
a rigorous implementation study because it identifies and quantifies where the
original roofline assumptions fail at the production interface.
