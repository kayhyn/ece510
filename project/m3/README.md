# Milestone 3 Deliverables

## File Catalog

- `README.md`: Catalog of all M3 files plus reproduction instructions.
- `rtl/top.sv`: Integrated top module that instantiates the M2 AXI4-Stream interface and M2 compute core with command-decoding glue.
- `tb/tb_top.sv`: End-to-end host-side co-simulation testbench for programming operands, starting compute, and reading back the result.
- `sim/cosim_run.log`: Icarus Verilog co-simulation transcript showing `PASS: m3 end-to-end cosim`.
- `sim/cosim_waveform.png`: Annotated waveform image showing host writes, compute activity, and host result readback.
- `synth/config.json`: OpenLane 2 configuration for the integrated `top` design using Sky130 HD and a 10 ns clock.
- `synth/openlane_run.log`: Full OpenLane 2 stdout/stderr transcript for the successful `M3_SYNTH` run through synthesis and pre-PNR STA.
- `synth/yosys_synthesis.log`: Supplemental standalone Yosys structural synthesis transcript retained for comparison.
- `synth/timing_report.txt`: OpenLane pre-PNR setup/hold timing report summary and worst-path details.
- `synth/area_report.txt`: OpenLane mapped Sky130 cell count and area report summary.
- `synth/power_report.txt`: OpenLane pre-PNR power estimate summary.
- `synth/critical_path.md`: Critical path identification and explanation from OpenLane STA.
- `tools/generate_waveform.py`: Script that regenerates `sim/cosim_waveform.png` from the co-simulation VCD.
- `synthesis_notes.md`: Narrative synthesis and scope-status report, including OpenLane failure details and M4 plan.

## Co-Simulation Reproduction

Simulator used:

- Icarus Verilog 11.0 (`iverilog`)
- Icarus Verilog runtime 11.0 (`vvp`)
- Python 3.10.12 with matplotlib 3.5.1 for waveform image generation

Run from the repository root:

```sh
iverilog -g2012 -Wall \
  -o project/m3/sim/top_tb.vvp \
  project/m2/rtl/interface.sv \
  project/m2/rtl/compute_core.sv \
  project/m3/rtl/top.sv \
  project/m3/tb/tb_top.sv

vvp project/m3/sim/top_tb.vvp > project/m3/sim/cosim_run.log 2>&1
python3 project/m3/tools/generate_waveform.py
```

Expected log excerpt:

```text
Representative 3x3 INT8 dot product expected=-110 observed=-110 response=bfffff92
PASS: m3 end-to-end cosim
```

The testbench drives only the host-side AXI4-Stream pins. It does not poke
`compute_core` directly.

## Synthesis Reproduction

OpenLane 2 used:

- OpenLane v2.3.10
- Version string in `openlane --version`: OpenLane v2.3.10
- Sky130 PDK provided by the OpenLane 2 Nix/Volare environment
- Runtime environment: OpenLane 2 Nix shell, invoked as root inside the course container

OpenLane command used from the repository root:

```sh
sudo env PATH="/nix/var/nix/profiles/default/bin:$PATH" \
  NIX_CONFIG="experimental-features = nix-command flakes" \
  nix shell --accept-flake-config github:efabless/openlane2/2.3.10 \
  -c bash -lc 'openlane --run-tag M3_SYNTH --overwrite --to OpenROAD.STAPrePNR project/m3/synth/config.json' \
  > project/m3/synth/openlane_run.log 2>&1
```

The committed transcript is `synth/openlane_run.log`. The run completes through
`OpenROAD.STAPrePNR`, then intentionally skips later place-and-route/signoff
steps because M3 requires synthesis, timing, area, power, and critical-path
reports rather than final routed GDS.

Important container setup note:
The distro `yosys` package must not shadow OpenLane's Nix-provided Yosys. If it
is installed, remove it before entering the Nix shell:

```sh
sudo apt-get remove -y yosys
```

Expected result:

- `openlane_run.log` ends with `Flow complete.`
- `area_report.txt` reports 2000 mapped cells and 23129.683200 um^2.
- `timing_report.txt` reports slow-corner setup WNS of -6.4845 ns and clean hold timing.
- `power_report.txt` reports pre-PNR total power estimates.
