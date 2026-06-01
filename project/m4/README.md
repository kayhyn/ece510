# Milestone 4 Deliverables -- 128-MAC Array

M4 scales the M2/M3 single 9-tap INT8 dot-product lane up to the project's
planned **128-MAC parallel array** (`mac_array`), verifies it cycle-accurately,
and pushes it through real OpenLane 2 synthesis + STA on the sky130 HD PDK. The
measured results feed the updated CF09 benchmark (measured vs. projected).

## File Catalog

- `rtl/mac_array.sv`: Pipelined 128-lane INT8 MAC array. One broadcast
  activation + 128 per-lane weights per cycle; 3-stage pipeline
  (capture / multiply / accumulate); streaming `valid/first/last` control.
  Sustains NUM_MAC MACs/cycle.
- `tb/tb_mac_array.sv`: Cycle-accurate testbench. Streams a representative
  slice of the dominant 3x3 INT8 conv (8 output pixels, L=576 reduction each,
  128 channels), checks every result against an independent SV reference, and
  measures sustained MACs/cycle.
- `sim/cosim_run.log`: Icarus Verilog transcript (`PASS: m4 128-MAC array
  end-to-end`, 0 errors, 127.916 MAC/cycle).
- `synth/config.json`: OpenLane 2 config for the full `mac_array`, 4.0 ns clk.
- `synth/openlane_run.log`: OpenLane transcript for the full 128-lane array,
  `--to OpenROAD.STAPrePNR` (run tag M4_SYNTH) -> real area + power.
- `synth/config_lane.json` + `synth/lane_wrap.sv`: single-lane
  (`mac_array #(.NUM_MAC(1))`) config used to obtain the real placed datapath
  Fmax without the bare array's 5,134-pin floorplan artifact.
- `synth/openlane_lane.log`: OpenLane transcript for the single lane through
  placement + STA (`--to OpenROAD.STAMidPNR`, run tag M4_LANE) -> real Fmax.
- `synth/openlane_pnr.log`: full-array placement attempt (documents the
  5,134-IO-pin / placement-density artifacts; see timing_report.txt section A).
- `synth/area_report.txt`, `synth/power_report.txt`, `synth/timing_report.txt`:
  Extracted real area, power, and timing summaries.
- `synth/synth_area.ys`: standalone yosys area cross-check script.

## Co-Simulation Reproduction

Simulator: Icarus Verilog 11/12 (`iverilog -g2012`, `vvp`).

```sh
iverilog -g2012 -o project/m4/sim/mac_array_tb.vvp \
  project/m4/rtl/mac_array.sv project/m4/tb/tb_mac_array.sv
vvp project/m4/sim/mac_array_tb.vvp
```

Expected: `pixels_captured=8  errors=0`, `sustained_macs_per_cycle=127.916`,
`PASS: m4 128-MAC array end-to-end`.

## Synthesis Reproduction

A container engine is required for OpenROAD. This run used colima
(`brew install colima && colima start --cpu 4 --memory 8 --disk 60`) and the
OpenLane 2 image, invoked directly (the `--dockerized` wrapper needs a TTY):

```sh
docker run --rm \
  -v "$PWD":/work -v "$HOME/.volare":/root/.volare -e PDK_ROOT=/root/.volare \
  -w /work ghcr.io/efabless/openlane2:2.3.10 \
  openlane --run-tag M4_SYNTH --overwrite --to OpenROAD.STAPrePNR \
  /work/project/m4/synth/config.json
```

Expected: `Flow complete.`; 99,710 mapped cells; 1,065,403 um^2; per-corner
pre-PNR power ~193-343 mW. See `synthesis_notes.md` for the timing story (the
pre-PNR setup result is dominated by unbuffered high-fanout broadcast nets; a
buffered post-CTS STA is run separately for a meaningful Fmax).
