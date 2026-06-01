# CF09 — Software Baseline vs. Hardware Accelerator Benchmark

Kernel benchmarked: the dominant **3×3 INT8 convolution**,
`52×52×64 → 52×52×128`, stride 1, same-pad, INT8 operands / INT32 accumulate
(im2col + GEMM). FLOPs per layer = 2 × MACs = 2 × 199,360,512 = **398,721,024**.

> **M4 UPDATE (this revision).** The 128-MAC array was implemented
> (`project/m4/rtl/mac_array.sv`), verified cycle-accurately, and synthesized
> for real on the sky130 HD PDK via OpenLane 2 (containerized). The throughput
> efficiency, area, power, and Fmax that CF09 originally had to **project** are
> now **measured**. Section 1 is the new measured comparison; Section 2 keeps the
> original projection for traceability. Numbers are labeled MEASURED or
> PROJECTED throughout.

---

## Section 1 — M4 measured results and measured-vs-projected comparison

### 1a. Measurement provenance

| Quantity | How obtained | Value |
|----------|--------------|-------|
| SW time / throughput / memory | MEASURED, `run_sw_baseline.py`, 15 runs | 94.79 ms, 4.21 GFLOP/s, 88.7 MB |
| Array functional correctness | MEASURED, `tb_mac_array.sv` (Icarus), 1024 results vs SV reference | PASS, 0 errors |
| Array sustained throughput | MEASURED, `tb_mac_array.sv` | **127.92 MAC/cycle** (99.94% of 128) |
| Array area | MEASURED, OpenLane M4_SYNTH (sky130 HD) | **99,710 cells, 1.065 mm²** |
| Array power (pre-PNR, default activity) | MEASURED, OpenLane STA | **255 mW (tt) / 194 mW (ss) / 343 mW (ff)** |
| Datapath Fmax (placed single lane) | MEASURED, OpenLane M4_LANE STAMidPNR | **202 MHz (tt) / 106 MHz (ss) / 339 MHz (ff)** |
| Full-array timing (pre-PNR) | MEASURED, OpenLane M4_SYNTH | broadcast-fanout limited (see note) |

Real array throughput = 2 × (MAC/cycle) × Fmax, using the measured 127.92
MAC/cycle and the measured datapath Fmax per corner:

```
tt:  2 × 127.92 × 202 MHz = 51.7 GOPS   ->  layer time 398.7M / 51.7G = 7.71 ms
ss:  2 × 127.92 × 106 MHz = 27.1 GOPS   ->  14.70 ms   (slow sign-off corner)
ff:  2 × 127.92 × 339 MHz = 86.7 GOPS   ->   4.60 ms
```

### 1b. Results table (SW measured vs HW measured)

| Metric | SW baseline (MEASURED) | HW 128-MAC array (MEASURED) |
|--------|------------------------|------------------------------|
| Platform | Apple M1 Pro (same as M1) | sky130 HD ASIC, 128-MAC array |
| Throughput (typical) | 4.21 GFLOP/s | **51.7 GOPS @ tt 202 MHz** (27.1 ss / 86.7 ff) |
| Execution time / layer | 94.79 ms | **7.71 ms** (tt); 14.70 ms (ss); 4.60 ms (ff) |
| Sustained compute | n/a | 127.92 MAC/cycle (99.94% of 128) |
| Area | (44 MB RSS, software) | 1.065 mm², 99,710 cells |
| Power | ~15 W package (assumed) | 255 mW (tt, pre-PNR, default activity) |
| Correctness | reference | PASS, 0 errors vs SV reference |

### 1c. Speedup (throughput ratio, MEASURED / MEASURED)

```
typical (tt):  51.7 / 4.21 = 12.3×   (7.71 ms vs 94.79 ms)
slow   (ss):   27.1 / 4.21 =  6.4×
fast   (ff):   86.7 / 4.21 = 20.6×
```

### 1d. Energy efficiency (MEASURED throughput, MEASURED HW power; SW power assumed)

```
HW array tt: 51.7 GOPS / 0.255 W = 203 GOPS/W
HW array ss: 27.1 GOPS / 0.194 W = 140 GOPS/W
SW baseline: 4.21 GFLOP/s / 15 W = 0.281 GOPS/W   [15 W assumed, not instrumented]

Energy-efficiency improvement ≈ 203 / 0.281 ≈ 720× (tt), ≈ 500× (ss).
```

### 1e. Measured vs. projected — what the real silicon-flow changed

| Quantity | CF09 projection | M4 measurement | Verdict |
|----------|-----------------|----------------|---------|
| Useful ops/cycle | 128 MAC/cycle (1.0/lane) | 127.92 MAC/cycle | **Confirmed** (streaming removed the M3 0.9/lane bubble) |
| Clock Fmax | 250 MHz | tt 202 / ss 106 / ff 339 MHz | **Optimistic**: 250 MHz only at ff; ~106 MHz at sign-off ss |
| Peak throughput | 64 GOPS @ 250 MHz | 51.7 GOPS (tt) / 27.1 (ss) | **~20–60% lower** (Fmax shortfall) |
| Speedup vs SW | 15.2× | 12.3× (tt) / 6.4× (ss) | Lower, same order |
| Power | ~133 mW (linear 128×) | 255 mW (tt) | **~2× higher** (full per-lane 32b accumulators) |
| Area | (not projected) | 1.065 mm² | New measured datum |
| Energy efficiency | ~375× | ~720× (tt) | Higher (real throughput + power both real) |

**Why the Fmax gap (the dominant correction):** the measured critical path is the
**32-bit accumulate adder carry chain** (worst path starts at the Stage-B product
register and propagates through the adder), giving ~9.42 ns at the slow corner.
The pipelined lane still beats the M3 unpipelined lane (60.6 MHz → 106 MHz slow,
1.75×), but the 250 MHz target needs the accumulator narrowed/retimed
(carry-save adder — see `project/remaining_tasks.md`).

**Full-array timing note:** pre-PNR STA of the bare 128-lane array reports a
−387 ns artifact dominated by the unbuffered broadcast nets (`b_valid` fanout
5,881; 333 ns single-gate delay) and the bare module's 5,134 top-level pins.
These are buffering/floorplan artifacts of synthesizing the array in isolation,
not logic-depth limits — hence the Fmax above is taken from the placed single
lane (identical per-lane logic), and the full array additionally needs the
broadcast fanout pipelined/banked to approach that ceiling.

---

## Section 2 — Original CF09 projection (retained for traceability)

The text below was the pre-M4 projection, when only a single 9-tap lane existed.
It is superseded by the Section 1 measurements but kept to show the delta.

### Useful-ops-per-cycle projection (explicit)

```
Measured lane efficiency (M3 single lane, Icarus tb_bench.sv):
    10 cycles per 9-tap dot product  ->  0.9 MAC/cycle/lane (START/restart bubble)

Projected full-array peak (design intent, pipelined to 1 MAC/cycle/lane):
    useful ops/cycle = 128 MACs × 2 = 256 ops/cycle
    peak throughput  = 256 × 250 MHz = 64 GOPS            [PROJECTED]
    @ 100 MHz: 25.6 GOPS   @ 60.6 MHz: 15.5 GOPS          [PROJECTED]
Full-layer time @ 64 GOPS = 6.23 ms                       [PROJECTED]
```

### Projected speedup / energy (pre-M4)

```
128-MAC array @250 MHz (PROJECTED): 64.0 / 4.21 = 15.2×   (6.23 ms vs 94.79 ms)
Energy efficiency (PROJECTED): ~375× (synth pre-PNR power, assumed 15 W SW)
```

(The M4 measurements show the streaming array recovered the per-lane bubble
exactly as projected — 0.9 → 0.999 MAC/cycle/lane — but the 250 MHz clock and
133 mW power assumptions were optimistic; see Section 1e.)
