# M4 Synthesis and Verification Notes -- 128-MAC Array

Milestone 4 builds the project's planned **128-MAC INT8 array** (`mac_array`),
the parallel scale-up of the M2/M3 single 9-tap lane, and runs the real
analysis (cycle-accurate simulation + OpenLane 2 synthesis/STA on sky130 HD).
This closes the gap that CF09 part 2 had to leave as *projected*: the array now
physically exists, so throughput efficiency, area, and power are measured.

## Architecture

`mac_array` is an output-stationary, weight-streaming array of NUM_MAC=128
lanes. Each cycle one INT8 activation is broadcast to all lanes and 128 per-lane
INT8 weights are presented; lane i computes output channel i. A full 3x3
convolution output pixel streams its K = Kh*Kw*Cin = 576 reduction elements
through the array, and the 128 lanes emit 128 output channels in parallel.

The datapath is pipelined into three stages -- capture, signed 8x8 multiply,
sign-extend + 32-bit accumulate -- explicitly removing the M3 critical path's
serial tap-select-mux -> multiply -> add. Streaming `valid/first/last` tags
travel with the data so accumulations for back-to-back pixels run with no
bubble. This is the fix for the M3 single lane's measured 0.9 MAC/cycle restart
penalty.

## Functional verification (cycle-accurate, Icarus Verilog)

`tb_mac_array.sv` streams 8 representative output pixels (L=576, 128 channels)
back-to-back and checks every one of the 8x128 = 1024 results against an
independent SystemVerilog reference dot product.

  pixels_captured = 8, errors = 0  ->  PASS: m4 128-MAC array end-to-end
  total_macs = 589,824 over stream_cycles = 4,611
  **sustained throughput = 127.916 MAC/cycle = 99.94% of the 128-MAC peak**

This is the headline measured result: the array sustains essentially the full
128 MACs/cycle (the 0.06% shortfall is pipeline fill/drain over the finite
stream), validating the "useful ops/cycle" half of the CF09 64 GOPS projection.

## Synthesis area (OpenLane 2, real)

Run tag M4_SYNTH, `--to OpenROAD.STAPrePNR`, sky130_fd_sc_hd:

  99,710 mapped cells, 1,065,403 um^2 (1.065 mm^2), 0 unmapped, 0 latches.
  vs M3 single lane: 2,000 cells / 23,130 um^2  ->  ~46x for 128 lanes.

The 11,279 flip-flops match 128 x (8b weight + 16b product + 32b acc + 32b
result) plus shared control tags. Multipliers and accumulators dominate area.

## Power (OpenLane 2, pre-PNR, default activity)

  tt 255.4 mW, ss 193.5 mW, ff 342.5 mW (tt: 51% sequential / 49% combinational).
  vs M3 single lane ~1.569 mW.

This is ~2x the crude 133 mW linear projection in CF09, because the real array
carries full 32-bit accumulators and pipeline registers per lane. It is pre-PNR
with default activity and should be re-annotated from the workload VCD in
signoff.

## Timing -- the real finding

At the 250 MHz (4 ns) target, **pre-PNR STA reports a catastrophic -387 ns setup
WNS, but this is not a real Fmax.** The worst path starts at the flip-flop
driving the `b_valid` control net, which has **fanout 5881** and ~81 ns slew,
then an unbuffered inverter driving a fanout-2313 net contributes a single-gate
delay of **333.7 ns**. The shared broadcast signals (activation, valid, first,
last) drive all 128 lanes, and pre-PNR there is no buffer insertion or
clock-tree synthesis, so one driver sees pF-scale load. The pipeline *logic*
depth (8x8 multiply; 32-bit add) is short; the violation is pure interconnect
fanout. This is why a buffered post-CTS STA (`--to OpenROAD.STAMidPNR`,
run tag M4_PNR) is run to obtain a meaningful Fmax -- see timing_report.txt
section (B).

To get a meaningful Fmax for the datapath itself (without the broadcast-fanout
artifact, and small enough to place/route), a single pipelined lane
(`lane_wrap` = `mac_array #(.NUM_MAC(1))`) was taken through placement + STA
(run tag M4_LANE). The 128 lanes share this exact per-lane logic, so this is the
datapath ceiling. At the 4.0 ns (250 MHz) target:

  ff: +1.05 ns -> ~339 MHz (meets 250)   tt: -0.94 ns -> ~202 MHz
  ss (sign-off): -5.42 ns -> ~106 MHz (9.42 ns)

The worst path starts at the Stage-B product register `lane[0].bprod[15]` and
runs through the **32-bit accumulate adder carry chain** -- the dominant logic
stage. So the pipelined datapath does NOT meet 250 MHz at the slow corner
(only at the fast corner); it reaches ~106 MHz (ss) / ~202 MHz (tt) -- still a
1.75x slow-corner improvement over the M3 unpipelined lane (60.6 MHz).

Practical consequences (the real-vs-projected gaps, carried into CF09):
  1. Fmax: projected 250 MHz is optimistic for sign-off; real datapath is
     ~106 MHz (ss) / ~202 MHz (tt). Limiter = 32-bit accumulate adder ->
     motivates the carry-save-adder change in project/remaining_tasks.md.
  2. The full array's clock is bounded by this ceiling AND the broadcast buffer
     tree, so reaching ~200 MHz on the full array also needs the broadcast
     activation/valid/first/last fanout to be pipelined or banked.
  3. Compute parallelism (127.92 MAC/cycle) and functional correctness are
     fully confirmed; the open risk is purely timing closure, not parallelism.
