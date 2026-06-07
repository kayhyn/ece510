# M4 Synthesis and Verification Notes -- 128-MAC Accelerator

This is the supplementary narrative for the M4 synthesis runs. The
authoritative tables are in `synth/timing_report.txt`, `synth/area_report.txt`,
`synth/power_report.txt`, and `bench/benchmark.md`; the report
(`report/design_justification.pdf`) ties them together. This file just
captures the engineering context.

## Architecture (as built)

The compute core `mac_array` is an output-stationary, weight-streaming array
of NUM_MAC=128 lanes. Each cycle one INT8 activation is broadcast to all
lanes and 128 per-lane INT8 weights are presented; lane i computes output
channel i. A full 3x3 convolution output pixel streams its K = Kh*Kw*Cin =
576 reduction elements through the array, and the 128 lanes emit 128 output
channels in parallel.

The datapath is **3-stage pipelined** -- capture, signed 8x8 multiply,
sign-extend + **carry-save accumulate** -- explicitly removing the M3
critical path's serial tap-select-mux -> multiply -> add. Streaming
`valid/first/last` tags travel with the data so accumulations for back-to-back
pixels run with no bubble. The accumulator is held in redundant (sum, carry)
form across the reduction; the only full carry-propagate add happens on
`last`. This removes the 32-bit ripple-carry adder from the inner loop and
moves the critical path onto the 8x8 multiplier.

The production top wrapper `accel_top` adds:
  - **128 per-lane weight banks** (single-port, L_MAX entries x 8b each;
    declared via a generate block so each lane has its own private bank --
    necessary to keep yosys from inferring a 128-read-port multi-port memory
    that explodes into millions of muxes);
  - a **banked broadcast fan-out tree** (one cycle of registered fan-out;
    8 banks of 16 lanes each so no shared net drives more than ~16 sinks);
  - a **result serializer** (latches all 128 INT32 channel results on the
    array's `out_valid` pulse, drains one per beat over a 64-bit
    AXI4-Stream output).
The top-level pin count drops from a bare-array 5,134 to 137.

## Functional verification (cycle-accurate, Icarus Verilog)

Both end-to-end testbenches stream 8 output pixels (L=576, 128 channels)
back-to-back and check every one of the 8x128 = 1024 results against an
independent SystemVerilog reference dot product.

* `tb_top.sv` (bus-natural interface, `stream_if` + `compute_core`):
    pixels_captured = 8, errors = 0  ->  PASS
    sustained throughput = **127.861 MAC/cycle = 99.89% of peak**
* `tb_accel_top.sv` (production AXI4-Stream interface, `accel_top`):
    pixels_captured = 8, errors = 0  ->  PASS
    sustained throughput = **128.000 MAC/cycle during compute phase**
    (the 1,024-beat result drain is amortized over the layer)

## Synthesis runs (OpenLane 2, sky130_fd_sc_hd)

The synthesis story has two runs, both on the post-CSA RTL:

1. **`M4_CSA_LANE`** -- `lane_wrap = mac_array #(.NUM_MAC(1))`, full PnR.
   Gives the placed-and-routed datapath Fmax. The 128 lanes share identical
   per-lane logic, so this is the per-cell ceiling the full array converges
   to. DRC/LVS clean post-detailed-route. Worst path is now the 8x8 signed
   multiplier (Stage A weight -> Stage B product flop) -- confirming the
   carry-save accumulator successfully removed the 32-bit adder from the
   critical path.

2. **`M4_ACCEL`** -- the production `accel_top`, full PnR. Realistic 137-pin
   top-level with on-chip weight banks (L_MAX=64 for the sky130 inferred
   register-file flow; the architecture is L_MAX-parametric), banked
   broadcast, and the result serializer.

Open caveats (carried into the report's *What did not work*):
  1. **Fmax still misses the 250 MHz / 64 GFLOP/s target** at the slow
     sign-off corner: ~113 MHz (ss) / ~215 MHz (tt) / ~333 MHz (ff). The
     8x8 multiplier is the new limiter. Closing to 250 MHz at ss would
     require pipelining the multiplier into two registered stages.
  2. **Power is post-PnR with default switching activity**, not
     workload-annotated; the cleanest remaining improvement is to re-run
     OpenROAD power with a VCD/SAIF from `tb_accel_top`.
  3. The `accel_top` PnR uses **`L_MAX=64`**; the architecture is L_MAX-
     parametric and a real ASIC would back the 576-deep weight bank with
     sky130 SRAM macros via the OpenLane macro flow.

Compute parallelism (127.861 MAC/cycle) and functional correctness are
fully confirmed; the remaining open risk is timing closure.
