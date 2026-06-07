# M4 Benchmark: 128-MAC Accelerator vs. M1 Software Baseline

This document reports the **measured** M4 accelerator throughput and energy for
the dominant 3x3 INT8 convolution kernel and compares them to the M1 software
baseline. Every number traces to a committed file (see *Traceability* below);
the raw values are in [`benchmark_data.csv`](benchmark_data.csv) and the
[`roofline_final.png`](roofline_final.png) plots the measured accelerator point.

## Workload

The benchmarked kernel is the dominant layer profiled in M1: a 3x3, stride-1,
same-padding INT8 convolution, input 52x52x64, output 52x52x128.

| Quantity | Value | Source |
|---|---|---|
| Output pixels (spatial) | 52 x 52 = 2,704 | M1 |
| Output channels | 128 (= NUM_MAC lanes) | design |
| Reduction length L per pixel | 3x3x64 = 576 | M1 |
| MACs per layer | 2,704 x 128 x 576 = **199,360,512** | derived |
| FLOPs per layer (2 FLOP/MAC) | **398,721,024** | M1 `sw_baseline.md` |
| Operand bytes (no reuse) | 173,056 + 73,728 + 346,112 = 592,896 B | M1 `interface_selection.md` |
| Arithmetic intensity | **672.5 FLOP/byte** (compute-bound) | derived |

## Method of measurement

1. **Useful work per cycle (RTL simulation).** `tb_top.sv` streams 8 output
   pixels (L=576 each, 128 channels) end-to-end through the integrated `top`
   (AXI4-Stream `stream_if` -> `compute_core` -> `mac_array`) and checks every
   one of the 8x128 = 1,024 results against an independent SystemVerilog
   reference. From `sim/final_run.log`:

   ```
   total_macs=589824  stream_cycles=4613  errors=0
   sustained_macs_per_cycle = 589824 / 4613 = 127.861  (99.89% of the 128 peak)
   ```

   The 0.11% shortfall is pipeline fill/drain over the finite 8-pixel stream
   (interface 1-cycle register + 3-stage core); for the full 2,704-pixel layer
   it is negligible. Sustained compute = 127.861 MAC/cycle.

2. **Clock frequency (post-synthesis STA).** Frequency is taken from the
   OpenLane 2 placed single-lane STA (`synth/timing_report.txt`, section B); the
   128 lanes share identical per-lane logic so this is the datapath ceiling:
   sign-off slow corner **106 MHz (ss)**, typical **202 MHz (tt)**, fast
   **339 MHz (ff)**. The M1 design target of 250 MHz is **not met at the
   sign-off corner** (the 32-bit accumulate adder carry chain is the limiter).

3. **Layer time** = (layer MACs / sustained MAC-per-cycle) / frequency.
   **Throughput** = layer FLOPs / layer time. **Energy** = corner power
   (`synth/power_report.txt`) x layer time.

## Throughput and speedup vs. M1

M1 software baseline: median **160.9 ms/layer** -> **2.48 GFLOP/s**
(`project/m1/sw_baseline.md`).

| Configuration | Freq | Layer time | Throughput | **Speedup vs M1** |
|---|---|---|---|---|
| M1 software baseline | - | 160.9 ms | 2.48 GFLOP/s | 1.00x |
| M4 accel, ss (sign-off) | 106 MHz | 14.69 ms | 27.2 GFLOP/s | **10.96x** |
| M4 accel, tt (typical) | 202 MHz | 7.70 ms | 51.8 GFLOP/s | **20.89x** |
| M4 accel, ff (fast) | 339 MHz | 4.60 ms | 86.7 GFLOP/s | 34.98x |
| M4 accel, 250 MHz target | 250 MHz | 6.24 ms | 63.9 GFLOP/s | 25.80x |

**Headline measured result: 10.96x (guaranteed sign-off, ss) to 20.89x (typical,
tt) speedup over the M1 NumPy baseline**, for the same INT8 kernel and the same
FLOP/s metric. The 250 MHz / 64 GFLOP/s row is the M1 *design target*, included
for reference only; it is not met at sign-off and is **not** the measured point
plotted on the roofline. The roofline's M4 markers are the measured tt (51.8)
and ss (27.2) GFLOP/s values.

## Energy comparison (estimated)

Accelerator energy = synthesis power x measured layer runtime:

| Configuration | Power | Energy/layer | Energy efficiency |
|---|---|---|---|
| M4 accel, ss | 193 mW | 2.84 mJ | 140 GFLOP/s/W |
| M4 accel, tt | 255 mW | 1.97 mJ | 203 GFLOP/s/W |

For the software baseline, no wall-plug measurement was taken, so an **assumed**
Apple M1 Pro CPU active power of **15 W** is used (conservative for a
multi-core-backed NumPy/Accelerate path; the package can draw more). At 160.9 ms
that is ~2,414 mJ/layer and an efficiency of **0.165 GFLOP/s/W**.

- Energy/layer ratio (tt): 2,414 mJ / 1.97 mJ ~= **1,200x lower energy**.
- Efficiency ratio (tt): 203 / 0.165 ~= **1,200x better GFLOP/s/W**.

This is an order-of-magnitude estimate, explicitly gated on the 15 W assumption
and on a pre-PNR / default-activity power figure (see *Caveats*); it is reported
as "valued but optional" per the M4 checklist, not as a measured wall-plug
number.

## Gap between measured and theoretical

- **Compute parallelism is essentially ideal:** 127.861 of 128 MAC/cycle
  (99.89%). The output-stationary, weight-streaming dataflow with `first/last`
  tags removes the M3 single-lane restart bubble (M3 sustained only ~0.9
  MAC/cycle). So the throughput gap is **not** in utilization.
- **The gap is clock frequency.** The M1 projection assumed 250 MHz (64
  GFLOP/s). The placed datapath closes at only 106 MHz (ss) / 202 MHz (tt)
  because the 32-bit ripple-carry accumulate adder is the critical path. This is
  why measured tt throughput (51.8 GFLOP/s) is ~0.81x of the 64 GFLOP/s target,
  and ss (27.2) is ~0.42x. The fix (carry-save accumulator) is documented in
  `project/remaining_tasks.md` and the report's *What did not work* section.
- **Not interface-bound.** Required operand bandwidth at tt throughput is
  ~0.10 GB/s; the on-chip streaming path provides ~32 GB/s and the AXI4-Stream
  link ~0.4 GB/s, both far above demand (AI 672 >> ridge ~2). The roofline shows
  the kernel deep in the compute-bound region, so frequency, not bandwidth,
  bounds it.

## Caveats

- Power is OpenLane **pre-PNR with default switching activity** and no
  clock-tree; it is an early upper-ish estimate, to be re-annotated from a
  workload VCD after place-and-route (`remaining_tasks.md` task 3).
- Frequency is from the **placed single lane**; the full 128-lane array's clock
  is additionally bounded by the broadcast-net buffer tree (timing_report.txt
  section A), so the full-array clock may be at or below the per-lane ceiling
  until the broadcast fan-out is pipelined/banked.

## Traceability

| Number | File |
|---|---|
| 160.9 ms, 2.48 GFLOP/s baseline | `project/m1/sw_baseline.md` |
| 127.861 MAC/cycle, 4613 cycles, 0 errors | `project/m4/sim/final_run.log` |
| 106 / 202 / 339 MHz per corner | `project/m4/synth/timing_report.txt` |
| 193 / 255 / 343 mW per corner | `project/m4/synth/power_report.txt` |
| all derived throughput/speedup/energy rows | `project/m4/bench/benchmark_data.csv` |
| roofline point coordinates | `project/m4/tools/benchmark.py` -> `roofline_final.png` |
