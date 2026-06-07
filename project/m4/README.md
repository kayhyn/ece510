# Milestone 4 Deliverables -- 128-MAC INT8 Convolution Accelerator

M4 is the complete, synthesizable, verified, and benchmarked deliverable for the
project's **128-MAC INT8 array** that accelerates the dominant 3x3 convolution of
YOLO-nano. The compute core scales the M2/M3 single 9-tap dot-product lane up to
128 parallel lanes with a 3-stage pipeline and a carry-save accumulator; it is
wrapped (`accel_top`) with on-chip per-lane weight memory, a banked broadcast
fan-out tree, and a result serializer so that the full design routes through
OpenLane 2 on sky130 HD with a realistic ~140-pin top-level. The design is
verified cycle-accurately end-to-end through both a bus-natural testbench
(`tb_top`) and the production AXI4-Stream testbench (`tb_accel_top`), and
benchmarked against the M1 software baseline.

**Start here:** the design justification report is
[`report/design_justification.pdf`](report/design_justification.pdf) (9 sections,
~3,500 words). The measured headline: the array sustains **127.861 of 128
MAC/cycle (99.89%)** with **0 functional errors**, giving an **11.68x
(sign-off, 113 MHz) to 22.18x (typical, 215 MHz)** speedup over the 160.9 ms
M1 baseline. Both top-levels route cleanly through OpenLane 2 sky130 HD:
the single placed lane is DRC/LVS clean post-detailed-route, and `accel_top`
takes the full 128-lane array + weight memory + serializer through the same
flow at a realistic pin count.

## Diff from M3 (what changed)

- Compute scaled from **1 lane -> 128 lanes** (`rtl/mac_array.sv`), 3-stage
  pipelined, output-stationary/weight-streaming with `valid/first/last`
  streaming control (removes the M3 ~0.9 MAC/cycle restart bubble).
- Accumulator changed from a per-cycle 32-bit ripple-carry add to a
  **carry-save** running (sum, carry) pair with a single full add only on
  `last` -- removes the 32-bit adder carry chain from the inner-loop critical
  path.
- Production top wrapper `accel_top` adds **on-chip weight memory** (128
  per-lane single-port banks), a **banked broadcast tree** (8 banks of 16
  lanes -- limits any net to ~16 sinks), and a **result serializer** (one
  channel per beat on a 64-bit AXI4-Stream output). Top-level pin count drops
  from a bare-array 5,134 to **137**, enabling full PnR.
- Interface widened from a **single-word AXI4-Stream command port**
  (M2/M3 `axis_interface`) to a **narrow 64-bit opcode-tagged AXI4-Stream
  port** (`rtl/accel_top.sv`); the bus-natural wide-bus `stream_if` in
  `rtl/interface.sv` is retained as the unit-level test interface.

## File Catalog

Every file in `project/m4/`, with the checklist deliverable / report section it
supports.

### Top level
- `README.md` -- this catalog (Deliverable 1, M4 folder README).
- `synthesis_notes.md` -- narrative synthesis/verification notes (supports
  report Sections 7 & 9; supplementary).
- `next_steps.md` -- earlier hardening brief (historical; the items in it are
  now implemented as the production `accel_top` and the carry-save accumulator).

### `rtl/` -- final source code (Deliverable 2; report Section 4)
- `rtl/accel_top.sv` -- **the production top wrapper synthesized for full PnR**:
  narrow AXI4-Stream + 128 per-lane weight banks + banked broadcast tree +
  result serializer + 128-lane `mac_array` instance.
- `rtl/mac_array.sv` -- **the 128-lane MAC compute core** with the 3-stage
  pipeline and the carry-save accumulator. Authoritative; instantiated by both
  `accel_top` and `top`.
- `rtl/top.sv` -- thinner unit-test wrapper: wires the bus-natural
  `stream_if` to `compute_core` (verified by `tb/tb_top.sv`).
- `rtl/compute_core.sv` -- named compute core; transparent wrapper that
  instantiates `mac_array` (no added logic).
- `rtl/interface.sv` -- `stream_if`, the wide-bus AXI4-Stream test interface
  used by `tb_top`.

### `tb/` -- final testbenches (Deliverable 2)
- `tb/tb_top.sv` -- **bus-natural end-to-end testbench**: drives `top`
  end-to-end through `stream_if`, checks all 1,024 results vs. an independent
  reference, measures sustained MAC/cycle. Produces `sim/final_run.log`
  (report Section 6).
- `tb/tb_accel_top.sv` -- **production end-to-end testbench**: drives
  `accel_top` through the narrow 64-bit AXI4-Stream port (weight-load
  phase + compute phase + serialized drain). Produces
  `sim/final_accel_run.log`.
- `tb/tb_mac_array.sv` -- supplementary core-only testbench that drives
  `mac_array` directly (produces `sim/cosim_run.log`; 127.916 MAC/cycle).

### `sim/` -- final simulation outputs (Deliverable 2)
- `sim/final_run.log` -- **final simulation log showing PASS** (0 errors,
  127.861 MAC/cycle) from `tb/tb_top.sv`.
- `sim/final_accel_run.log` -- production-wrapper end-to-end log (0 errors,
  128.000 MAC/cycle in the compute phase) from `tb/tb_accel_top.sv`.
- `sim/final_waveform.png` -- **annotated end-to-end waveform** (report Fig. 4).
- `sim/final_top.vcd` -- VCD from the final run (source for the waveform).
- `sim/cosim_run.log` -- supplementary core-only run log (from `tb_mac_array`).

### `synth/` -- final synthesis results (Deliverable 3; report Section 7)
- `synth/config_accel.json` -- **OpenLane 2 config for `accel_top`**: full PnR
  on sky130 HD at a 6 ns target clock, `L_MAX=64` for the educational sky130
  inferred-register-file flow.
- `synth/config_lane.json`, `synth/lane_wrap.sv` -- single-lane config/wrapper
  used to obtain the real placed datapath Fmax with the carry-save accumulator
  (timing_report.txt section B).
- `synth/openlane_accel.log` -- **OpenLane run log** for `accel_top` (run tag
  `M4_ACCEL`).
- `synth/openlane_lane.log` -- OpenLane log for the placed single lane
  (`M4_LANE`, prior; the new CSA lane run is `M4_CSA_LANE` under
  `synth/runs/`).
- `synth/timing_report.txt` -- **timing report**: per-corner setup/hold WNS,
  critical path, closing frequency (113/215/333 MHz with CSA).
- `synth/area_report.txt` -- **area report**: lane stdcell count and area,
  128x extrapolation, dominant contributor.
- `synth/power_report.txt` -- **power report**: per-corner post-PnR per-lane
  power, naive 128x array extrapolation, full-array PnR numbers.
- `synth/config.json` -- earlier bare-`mac_array` config (kept for the
  historical 5,134-pin floorplan attempt referenced in report Section 9).
- `synth/openlane_run.log`, `synth/openlane_pnr.log` -- earlier OpenLane logs
  for the bare-array attempts (historical).
- `synth/synth_area.ys`, `synth/yosys_stat.txt`, `synth/mac_array.netlist.v` --
  standalone yosys area cross-check script, stats, and netlist.
- `synth/lane_pnr_summary.rpt` -- post-detailed-route STA summary (per-corner
  WNS/TNS/hold table) extracted from the M4_CSA_LANE OpenLane run.
- `synth/lane_metrics.json` -- filtered post-PnR design metrics (area, cell
  counts by class, IO count, per-corner timing, antenna/DRC/LVS).
- `synth/lane_yosys_stat.rpt` -- full mapped cell breakdown by sky130 cell.
- `synth/lane_power_{tt,ss,ff}.rpt` -- per-corner OpenROAD post-PnR power.
- `synth/lane_critical_path_ss.rpt` -- the worst setup path in the slow corner
  (the multiplier path), copied from `max_ss_100C_1v60/max.rpt`.
- Full OpenLane run directories (`synth/runs/M4_CSA_LANE/`, `synth/runs/M4_ACCEL/`)
  are gitignored due to size (168 MB and ~4 GB respectively); the key reports
  above are the committed evidence.

### `bench/` -- hardware vs. software benchmark (Deliverable 4; report Section 8)
- `bench/benchmark.md` -- measured throughput, speedup vs. M1, energy estimate,
  method, and full traceability table.
- `bench/benchmark_data.csv` -- **raw measurement data** behind every reported
  number (per-corner frequency, time, throughput, speedup, power, energy).
- `bench/roofline_final.png` -- **final roofline**: target hardware roofline +
  M1 software baseline point + **measured** M4 accelerator points (report Fig. 1).

### `report/` -- design justification report (Deliverable 5)
- `report/design_justification.pdf` -- **the 9-section report** (the deliverable).
- `report/design_justification.md` -- markdown source (starting point, not the
  deliverable; kept for reproducibility).
- `report/figures/fig1_roofline.png` -- Fig. 1, roofline (Section 2/8).
- `report/figures/fig2_block_diagram.png` -- Fig. 2, block diagram (Section 4).
- `report/figures/fig3_dataflow.png` -- Fig. 3, dataflow diagram (Section 4).
- `report/figures/fig4_waveform.png` -- Fig. 4, annotated waveform (Section 6).

### `tools/` -- regeneration scripts (reproducibility)
- `tools/generate_waveform.py` -- regenerates `sim/final_waveform.png` from the VCD.
- `tools/benchmark.py` -- recomputes `bench/benchmark_data.csv` and renders
  `bench/roofline_final.png` from the measured cycle count + synthesis numbers.
- `tools/figures.py` -- renders the block/dataflow diagrams and assembles
  `report/figures/`.

## Reproduction

### Co-simulation (Icarus Verilog 11/12)

```sh
# Bus-natural testbench (produces final_run.log + waveform VCD).
iverilog -g2012 -Wall -o /tmp/top_tb.vvp \
  project/m4/rtl/mac_array.sv project/m4/rtl/compute_core.sv \
  project/m4/rtl/interface.sv project/m4/rtl/top.sv \
  project/m4/tb/tb_top.sv
vvp /tmp/top_tb.vvp > project/m4/sim/final_run.log 2>&1
python3 project/m4/tools/generate_waveform.py     # -> sim/final_waveform.png

# Production AXI4-Stream end-to-end (weight load + compute + drain).
iverilog -g2012 -Wall -o /tmp/accel_tb.vvp \
  project/m4/rtl/mac_array.sv project/m4/rtl/accel_top.sv \
  project/m4/tb/tb_accel_top.sv
vvp /tmp/accel_tb.vvp > project/m4/sim/final_accel_run.log 2>&1
```

Expected: `final_run.log` reports `pixels_captured=8 errors=0`,
`sustained_macs_per_cycle=127.861`, `PASS: m4 128-MAC array end-to-end`;
`final_accel_run.log` reports `errors=0`,
`sustained_macs_per_compute_cycle=128.000`,
`PASS: accel_top 128-MAC with weight mem + serializer`.

### Benchmark + report figures

```sh
python3 project/m4/tools/benchmark.py    # -> bench/benchmark_data.csv, roofline_final.png
python3 project/m4/tools/figures.py      # -> report/figures/*.png
( cd project/m4/report && pandoc design_justification.md \
    -o design_justification.pdf --pdf-engine=xelatex )
```

### Synthesis (OpenLane 2, sky130 HD)

A container engine is required (this run used colima + the OpenLane 2 image):

```sh
# Production top -- full PnR.
docker run --rm \
  -v "$PWD":/work -v "$HOME/.volare":/root/.volare -e PDK_ROOT=/root/.volare \
  -w /work ghcr.io/efabless/openlane2:2.3.10 \
  openlane --run-tag M4_ACCEL --overwrite \
  /work/project/m4/synth/config_accel.json

# Single placed lane -- datapath Fmax with carry-save accumulator.
docker run --rm \
  -v "$PWD":/work -v "$HOME/.volare":/root/.volare -e PDK_ROOT=/root/.volare \
  -w /work ghcr.io/efabless/openlane2:2.3.10 \
  openlane --run-tag M4_CSA_LANE --overwrite \
  /work/project/m4/synth/config_lane.json
```

Expected: `Flow complete.` on both runs; placed lane DRC/LVS clean at
13,129 um^2 / 2,498 stdcells; per-corner post-PnR Fmax 113 MHz (ss) /
215 MHz (tt) / 333 MHz (ff). See `synth/timing_report.txt` for the full
timing story (the 32-bit adder is no longer the limiter after CSA; the
multiplier is the new critical path).
