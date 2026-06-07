# Milestone 4 Deliverables -- 128-MAC INT8 Convolution Accelerator

M4 is the complete, synthesizable, verified, and benchmarked deliverable for the
project's **128-MAC INT8 array** that accelerates the dominant 3x3 convolution of
YOLO-nano. It scales the M2/M3 single 9-tap dot-product lane up to 128 parallel
lanes, verifies it cycle-accurately end-to-end through an AXI4-Stream interface,
pushes the compute core through OpenLane 2 synthesis + STA on sky130 HD, and
benchmarks the **measured** result against the M1 software baseline.

**Start here:** the design justification report is
[`report/design_justification.pdf`](report/design_justification.pdf) (9 sections,
~2,700 words). The measured headline: the array sustains **127.861 of 128
MAC/cycle (99.89%)** with **0 functional errors**, giving a **10.96x (sign-off,
106 MHz) to 20.89x (typical, 202 MHz)** speedup over the 160.9 ms M1 baseline.

## Diff from M3 (what changed)

- Compute scaled from **1 lane -> 128 lanes** (`rtl/mac_array.sv`), 3-stage
  pipelined, output-stationary/weight-streaming with `valid/first/last`
  streaming control (removes the M3 ~0.9 MAC/cycle restart bubble).
- Interface widened from a **single-word AXI4-Stream command port**
  (M2/M3 `axis_interface`) to a **wide streaming-data port** (`rtl/interface.sv`,
  `stream_if`) that feeds all 128 lanes per cycle.
- Synthesis target is the **compute core `mac_array`** standalone (the array
  dominates area/timing/power). `top`/`compute_core`/`stream_if` are the
  integration RTL, verified end-to-end in simulation (`tb/tb_top.sv`).

## File Catalog

Every file in `project/m4/`, with the checklist deliverable / report section it
supports.

### Top level
- `README.md` -- this catalog (Deliverable 1, M4 folder README).
- `synthesis_notes.md` -- narrative synthesis/verification notes (supports
  report Sections 7 & 9; supplementary).

### `rtl/` -- final source code (Deliverable 2; report Section 4)
- `rtl/top.sv` -- top module: wires `stream_if` to `compute_core` (full
  integration; verified by `tb/tb_top.sv`).
- `rtl/compute_core.sv` -- named compute core; transparent wrapper that
  instantiates `mac_array` (no added logic).
- `rtl/mac_array.sv` -- **the 128-lane MAC compute core that was synthesized and
  benchmarked** (authoritative; referenced by `synth/config.json`).
- `rtl/interface.sv` -- `stream_if`, the AXI4-Stream streaming interface
  (report Section 5).

### `tb/` -- final testbenches (Deliverable 2)
- `tb/tb_top.sv` -- **final testbench**: drives `top` end-to-end through the
  AXI4-Stream ports, checks all 1,024 results vs. an independent reference,
  measures sustained MAC/cycle. Produces `sim/final_run.log` (report Section 6).
- `tb/tb_mac_array.sv` -- supplementary core-only testbench that drives
  `mac_array` directly (produces `sim/cosim_run.log`; 127.916 MAC/cycle).

### `sim/` -- final simulation outputs (Deliverable 2)
- `sim/final_run.log` -- **final simulation log showing PASS** (0 errors,
  127.861 MAC/cycle) from `tb/tb_top.sv`.
- `sim/final_waveform.png` -- **annotated end-to-end waveform** (report Fig. 4).
- `sim/final_top.vcd` -- VCD from the final run (source for the waveform).
- `sim/cosim_run.log` -- supplementary core-only run log (from `tb_mac_array`).

### `synth/` -- final synthesis results (Deliverable 3; report Section 7)
- `synth/config.json` -- **OpenLane 2 config** used for the final run (4.0 ns,
  `mac_array`, sky130 HD).
- `synth/openlane_run.log` -- **OpenLane run log** (run tag M4_SYNTH).
- `synth/timing_report.txt` -- **timing report**: per-corner setup/hold WNS,
  critical path, closing frequency (106/202/339 MHz).
- `synth/area_report.txt` -- **area report**: 99,710 cells, 1,065,403 um^2, cell
  breakdown, dominant contributor.
- `synth/power_report.txt` -- **power report**: 193/255/343 mW per corner,
  seq/comb split.
- `synth/config_lane.json`, `synth/lane_wrap.sv` -- single-lane config/wrapper
  used to obtain the real placed datapath Fmax (timing_report.txt section B).
- `synth/openlane_lane.log` -- OpenLane log for the placed single lane (M4_LANE).
- `synth/openlane_pnr.log` -- full-array placement attempt (documents the
  5,134-pin floorplan artifact; report Section 9).
- `synth/synth_area.ys`, `synth/yosys_stat.txt`, `synth/mac_array.netlist.v` --
  standalone yosys area cross-check script, stats, and netlist.

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
iverilog -g2012 -Wall -o /tmp/top_tb.vvp \
  project/m4/rtl/mac_array.sv project/m4/rtl/compute_core.sv \
  project/m4/rtl/interface.sv project/m4/rtl/top.sv \
  project/m4/tb/tb_top.sv
vvp /tmp/top_tb.vvp > project/m4/sim/final_run.log 2>&1
python3 project/m4/tools/generate_waveform.py     # -> sim/final_waveform.png
```

Expected: `pixels_captured=8 errors=0`, `sustained_macs_per_cycle=127.861`,
`PASS: m4 128-MAC array end-to-end`.

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
docker run --rm \
  -v "$PWD":/work -v "$HOME/.volare":/root/.volare -e PDK_ROOT=/root/.volare \
  -w /work ghcr.io/efabless/openlane2:2.3.10 \
  openlane --run-tag M4_SYNTH --overwrite --to OpenROAD.STAPrePNR \
  /work/project/m4/synth/config.json
```

Expected: `Flow complete.`; 99,710 mapped cells; 1,065,403 um^2; per-corner
pre-PNR power ~193-343 mW. See `synthesis_notes.md` and `synth/timing_report.txt`
for the full timing story (the pre-PNR setup result is dominated by unbuffered
high-fanout broadcast nets; a placed single-lane STA gives the real datapath
Fmax).
