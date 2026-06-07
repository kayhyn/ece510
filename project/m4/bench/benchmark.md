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
   it is negligible. The production wrapper `accel_top` (with narrow
   AXI4-Stream + weight memory + result serializer) is independently verified
   by `tb_accel_top.sv` (see `sim/final_accel_run.log`) at **128.000 MAC/cycle
   during the compute phase**, with 1,024-beat result drain overhead amortized
   across pixels.

2. **Clock frequency (post-PnR STA).** Frequency is taken from the OpenLane 2
   placed-and-routed single-lane STA *with the carry-save accumulator*
   (`synth/timing_report.txt` section B, run tag `M4_CSA_LANE`); the 128 lanes
   share identical per-lane logic so this is the datapath ceiling: sign-off
   slow corner **113 MHz (ss)**, typical **215 MHz (tt)**, fast **333 MHz
   (ff)**. The M1 design target of 250 MHz is **not met at the sign-off
   corner** (the 8x8 multiplier is now the limiter after CSA removed the
   adder from the inner-loop critical path).

3. **Layer time** = (layer MACs / sustained MAC-per-cycle) / frequency.
   **Throughput** = layer FLOPs / layer time. **Energy** = corner power
   (`synth/power_report.txt`) x layer time.

## Throughput and speedup vs. M1

M1 software baseline: median **160.9 ms/layer** -> **2.48 GFLOP/s**
(`project/m1/sw_baseline.md`).

| Configuration | Freq | Layer time | Throughput | **Speedup vs M1** |
|---|---|---|---|---|
| M1 software baseline | - | 160.9 ms | 2.48 GFLOP/s | 1.00x |
| M4 accel, ss (sign-off) | 113 MHz | 13.77 ms | 28.95 GFLOP/s | **11.68x** |
| M4 accel, tt (typical) | 215 MHz | 7.26 ms | 54.96 GFLOP/s | **22.18x** |
| M4 accel, ff (fast) | 333 MHz | 4.69 ms | 85.09 GFLOP/s | 34.34x |
| M4 accel, 250 MHz target | 250 MHz | 6.24 ms | 63.93 GFLOP/s | 25.80x |

**Headline measured result: 11.68x (guaranteed sign-off, ss) to 22.18x (typical,
tt) speedup over the M1 NumPy baseline**, for the same INT8 kernel and the same
FLOP/s metric. The 250 MHz / 64 GFLOP/s row is the M1 *design target*, included
for reference only; it is not met at sign-off and is **not** the measured point
plotted on the roofline. The roofline's M4 markers are the measured tt (55.0)
and ss (29.0) GFLOP/s values.

## Energy comparison (estimated)

Accelerator energy = post-PnR per-corner power x measured layer runtime. Power
is taken as **per-lane post-PnR power x 128 lanes** (the per-lane number is
from the placed-and-routed M4_CSA_LANE run; see `synth/power_report.txt`).
This is a more accurate scaling than the previous pre-PnR / default-activity
full-array estimate because it includes CTS and timing-repair-buffer power.

| Configuration | Power (array est.) | Energy/layer | Energy efficiency |
|---|---|---|---|
| M4 accel, ss | 363 mW | 5.00 mJ | 79.7 GFLOP/s/W |
| M4 accel, tt | 460 mW | 3.34 mJ | 119.5 GFLOP/s/W |

For the software baseline, no wall-plug measurement was taken, so an **assumed**
Apple M1 Pro CPU active power of **15 W** is used (conservative for a
multi-core-backed NumPy/Accelerate path; the package can draw more). At 160.9 ms
that is ~2,414 mJ/layer and an efficiency of **0.165 GFLOP/s/W**.

- Energy/layer ratio (tt): 2,414 mJ / 3.34 mJ ~= **720x lower energy**.
- Efficiency ratio (tt): 119.5 / 0.165 ~= **720x better GFLOP/s/W**.

This is an order-of-magnitude estimate, explicitly gated on the 15 W assumption
and on a default-activity (not VCD-annotated) per-lane power figure (see
*Caveats*); it is reported as "valued but optional" per the M4 checklist, not as
a measured wall-plug number.

## Gap between measured and theoretical

- **Compute parallelism is essentially ideal:** 127.861 of 128 MAC/cycle
  (99.89%). The output-stationary, weight-streaming dataflow with `first/last`
  tags removes the M3 single-lane restart bubble (M3 sustained only ~0.9
  MAC/cycle). So the throughput gap is **not** in utilization.
- **The gap is clock frequency.** The M1 projection assumed 250 MHz (64
  GFLOP/s). The placed datapath closes at only 113 MHz (ss) / 215 MHz (tt)
  even after the carry-save accumulator removed the 32-bit ripple-carry adder
  from the inner-loop critical path. The new critical path is the 8x8 signed
  multiplier (Stage A weight -> Stage B product flop, ~25 logic levels at
  sky130). This is why measured tt throughput (55.0 GFLOP/s) is ~0.86x of the
  64 GFLOP/s target, and ss (29.0) is ~0.45x. Closing the remaining gap to
  250 MHz would require pipelining the multiplier (e.g., a registered Booth
  partial-product stage), documented in the report's *What did not work*
  section.
- **Not interface-bound.** Required operand bandwidth at tt throughput is
  ~0.10 GB/s; the on-chip streaming path provides ~32 GB/s and the AXI4-Stream
  link ~0.4 GB/s, both far above demand (AI 672 >> ridge ~2). The roofline shows
  the kernel deep in the compute-bound region, so frequency, not bandwidth,
  bounds it.

## Caveats

- Power is OpenLane **post-PnR with default switching activity** scaled from one
  placed lane to 128 lanes; it is an early upper-ish estimate. To make a final
  energy claim, the full `accel_top` should be re-power-estimated with a SAIF
  or VCD annotation from the `tb_accel_top` workload.
- Frequency is from the **placed-and-routed single lane**; the full 128-lane
  `accel_top` clock is additionally bounded by the banked broadcast buffer tree
  (`timing_report.txt` section A), so the full-array clock may be slightly
  below the per-lane ceiling.
- The deliverable `accel_top` PnR uses `L_MAX=64` to keep the inferred weight
  register file tractable; the architecture is `L_MAX`-parametric and a real
  ASIC would back the 576-deep weight bank with sky130 SRAM macros.

## Traceability

| Number | File |
|---|---|
| 160.9 ms, 2.48 GFLOP/s baseline | `project/m1/sw_baseline.md` |
| 127.861 MAC/cycle, 4613 cycles, 0 errors | `project/m4/sim/final_run.log` |
| 128.000 MAC/cycle (compute), accel_top end-to-end | `project/m4/sim/final_accel_run.log` |
| 113 / 215 / 333 MHz per corner (CSA lane PnR) | `project/m4/synth/timing_report.txt` |
| Per-lane 2.84 mW (ss) / 3.59 mW (tt) post-PnR | `project/m4/synth/power_report.txt` |
| all derived throughput/speedup/energy rows | `project/m4/bench/benchmark_data.csv` |
| roofline point coordinates | `project/m4/tools/benchmark.py` -> `roofline_final.png` |
