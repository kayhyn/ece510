# M4 Final Benchmark: Synthesized Production Chiplet vs. M1 Baseline

This benchmark reports the performance of the design that was actually
synthesized: `accel_top` with 128 INT8 MAC lanes, a narrow 64-bit AXI4-Stream
interface, serialized results, and `L_MAX=64` weight entries per lane. It does
not use the faster wide-bus unit-test wrapper or the single-lane timing ceiling
as the final accelerator measurement.

## Workload and final scope

The target layer is the M1 3x3 INT8 convolution:

| Quantity | Value |
|---|---:|
| Input / output shape | 52x52x64 -> 52x52x128 |
| Full reduction length | 3x3x64 = 576 |
| Production tile length | 64 |
| Tiles per full reduction | 9 |
| Useful work | 199,360,512 MACs = 398,721,024 FLOPs |

Because the synthesized production wrapper has `L_MAX=64`, the host loads and
executes nine 64-element tiles. The chiplet returns one INT32 partial sum per
channel for each tile, and the host adds the nine partials to reconstruct each
full 576-element result. The benchmark assumes the host performs one INT32 add
as each serialized partial beat arrives. This is the behavior modeled and
verified by `tb_top.sv`, so host accumulation adds no cycles beyond the counted
serialized-output beats. Host software orchestration, sliding-window generation,
padding, and final output conversion outside this streaming transaction
schedule are not measured.

## Verification and cycle measurement

`tb/tb_top.sv` instantiates the exact synthesized configuration and drives only
the production AXI4-Stream ports. It verifies eight representative pixels:

```text
partial_results_checked=9216 full_results_checked=1024
partial_errors=0 full_errors=0
total_cycles=87988
backpressure_cycles=3 backpressure_errors=0 unstalled_schedule_cycles=87985
PASS: final synthesized-config accel_top tiled 576-element reduction
```

The test deliberately stalls output `TREADY` for three cycles and verifies that
the serializer holds and resumes correctly. The measured 87,985-cycle
**unstalled** schedule, excluding that injected protocol-test stall, consists of:

```text
73,728 weight-load beats
 4,608 compute beats
 9,216 serialized result beats
   433 pipeline/host-protocol gap cycles
```

The 433-cycle residual is `6 cycles x 72 tile-pixels + 1`. The full-layer
cycle count therefore extrapolates directly from the validated transaction
schedule:

```text
weight loads             = 9 x 128 x 64             =    73,728 cycles
compute input            = 9 x 2,704 x 64           = 1,557,504 cycles
serialized partials      = 9 x 2,704 x 128          = 3,115,008 cycles
pipeline/protocol gaps   = 9 x 2,704 x 6 + 1        =   146,017 cycles
total                                                     4,892,257 cycles
```

This equals **40.750 useful MACs per total production-chiplet cycle**. The
internal MAC array can accept 128 MACs/cycle during a compute tile, but that is
not the end-to-end accelerator throughput because weight loading, serialization,
and the single-result-buffer protocol are mandatory.

## Frequency projection and final performance estimate

The final performance projection uses the full `accel_top` post-CTS
typical-corner setup result, not the routed single-lane datapath ceiling:

```text
6.0 ns target + 2.730896 ns setup WNS magnitude = 8.730896 ns
setup-limited projected frequency = 114.536 MHz
```

The wrapper has unresolved hold, setup, slew, and capacitance violations and
does not close timing. Therefore 114.536 MHz is not a demonstrated operating
frequency. It is a setup-limited projection used with the measured transaction
cycle schedule to make the required M4 accelerator-versus-software comparison.
The worst setup path ends at serialized output `m_tdata[26]`, reinforcing that
the production interface is the final full-wrapper limiter.

| Configuration | Layer time | Throughput | Speedup vs. M1 |
|---|---:|---:|---:|
| M1 NumPy baseline | 160.900 ms | 2.478 GFLOP/s | 1.00x |
| Final synthesized-config `accel_top` projection | **42.714 ms** | **9.335 GFLOP/s** | **3.77x** |

The cycle schedule is measured and the resulting speedup is projected. It is a
post-CTS estimate because the full wrapper does not close timing and detailed
routing did not complete. It is also an optimistic chiplet-schedule comparison:
M1 includes NumPy im2col/padding and output processing, while M4 excludes host
orchestration, sliding-window generation, padding, and final output conversion.
Therefore 3.77x is not a demonstrated end-to-end speedup. Summary values are in
`benchmark_data.csv`; every raw timing, cycle-category, extrapolation, and M1
run input is in `raw_measurements.csv`.

## Arithmetic intensity and interface effect

M1's **algorithmic arithmetic intensity** is 672.497 FLOP/byte. That value
assumes ideal reuse: the input feature map, weights, and final output are each
counted once.

The implemented chiplet moves more data because every command and result uses a
64-bit stream beat and every 64-element tile returns 128 partial sums:

```text
implemented stream bytes
  = 8 x (73,728 weight + 1,557,504 compute + 3,115,008 output beats)
  = 37,969,920 bytes/layer

implemented-interface AI
  = 398,721,024 FLOPs / 37,969,920 bytes
  = 10.501 FLOP/byte
```

At 114.536 MHz, one 64-bit stream direction is rated at 0.916 GB/s. The
implemented schedule requires approximately 0.889 GB/s of aggregate serialized
traffic. The mathematical convolution is compute-bound under ideal reuse, but
the final chiplet is primarily **interface/serialization-bound**. Figure
`roofline_final.png` shows both arithmetic-intensity points and the
cycle-measured, timing-projected production point.

## Energy estimate

The full `accel_top` post-CTS power report gives **1.018 W** at the typical
corner with default switching activity. Multiplying by the corrected runtime:

```text
energy/layer = 1.018 W x 42.714 ms = 43.483 mJ
efficiency   = 9.335 GFLOP/s / 1.018 W = 9.17 GFLOP/s/W
```

This is an estimate, not a measured wall-plug result. It is pre-detailed-route
and not workload-annotated. The 1.018 W report was analyzed under the 6.0 ns
target constraint rather than scaled to the slower setup-limited frequency, so
the multiplication above is conservative. No software energy ratio is claimed
because M1 CPU power was not measured.

## Gap from the original target

M1 targeted 64 GFLOP/s at 250 MHz with ideal on-chip reuse. Three observed
effects reduce projected final performance:

1. Full `accel_top` reaches approximately 114.5 MHz at the available post-CTS
   typical-corner snapshot.
2. The inferred weight storage was reduced from 576 to 64 entries per lane,
   requiring nine host-managed tiles.
3. The narrow result serializer returns 128 partial results per tile and cannot
   overlap the next tile result because the wrapper has one result buffer.

The compute core is not the dominant final bottleneck. A next design should use
SRAM macros for the full weights and a double-buffered or wider result path.

## Traceability

| Measurement | Source |
|---|---|
| M1 160.9 ms baseline | `project/m1/sw_baseline.md` |
| Tiled correctness and 87,985-cycle schedule | `project/m4/sim/final_run.log` |
| Full-array setup-limited 114.536 MHz projection | `project/m4/synth/accel_postcts_wns.rpt` |
| Full-array 1.018 W estimate | `project/m4/synth/accel_postcts_power.rpt` |
| Derived full-layer values | `project/m4/tools/benchmark.py` |
| Summary and derived final table | `project/m4/bench/benchmark_data.csv` |
| Raw timings, cycle categories, and extrapolation inputs | `project/m4/bench/raw_measurements.csv` |
