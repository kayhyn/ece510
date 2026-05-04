# Milestone 2 Reproducibility

## Overview

This M2 package implements the required non-optional RTL deliverables for the
YOLO-nano 3x3 INT8 convolution accelerator project:

- `rtl/compute_core.sv`: synthesizable INT8 dot-product compute core with INT32 accumulation.
- `rtl/interface.sv`: synthesizable AXI4-Stream command/response interface matching the M1 interface selection.
- `tb/tb_compute_core.sv`: self-checking compute-core testbench.
- `tb/tb_interface.sv`: self-checking interface testbench.
- `sim/compute_core_run.log` and `sim/interface_run.log`: committed PASS transcripts.
- `sim/waveform.png`: representative annotated waveform image generated from simulator VCD traces.
- `precision.md`: optional INT8 data-format rationale and reproducible error analysis.
- `tools/generate_waveform.py`: regenerates `sim/waveform.png` from VCD files.
- `tools/precision_analysis.py`: regenerates `sim/precision_analysis.json`.

The file `interface.sv` uses module name `axis_interface` because `interface`
is a SystemVerilog keyword.

## Tool Versions Used

- Icarus Verilog 13.0 (`iverilog`)
- Icarus Verilog runtime 13.0 (`vvp`)
- Yosys 0.64
- Python 3.10.4
- NumPy 1.26.4
- matplotlib 3.7.1

## Run the Compute Core Testbench

From the repository root:

```sh
iverilog -g2012 -Wall \
  -o project/m2/sim/compute_core_tb.vvp \
  project/m2/rtl/compute_core.sv \
  project/m2/tb/tb_compute_core.sv

vvp project/m2/sim/compute_core_tb.vvp \
  > project/m2/sim/compute_core_run.log 2>&1
```

Expected output in `project/m2/sim/compute_core_run.log` includes:

```text
Representative 3x3 INT8 dot product expected=-110 result=-110
PASS: compute_core
```

## Run the Interface Testbench

From the repository root:

```sh
iverilog -g2012 -Wall \
  -o project/m2/sim/interface_tb.vvp \
  project/m2/rtl/interface.sv \
  project/m2/tb/tb_interface.sv

vvp project/m2/sim/interface_tb.vvp \
  > project/m2/sim/interface_run.log 2>&1
```

Expected output in `project/m2/sim/interface_run.log` includes:

```text
Write transaction stored config=00abcd1
Read response returned data=a00abcd1
PASS: interface
```

## Regenerate the Waveform Image

Run both testbenches first so `project/m2/sim/compute_core.vcd` and
`project/m2/sim/interface.vcd` exist, then run:

```sh
python3 project/m2/tools/generate_waveform.py
```

The script parses the actual VCD traces and writes
`project/m2/sim/waveform.png`. The VCD files are intermediate simulator output;
the required committed artifact is the PNG.

## Run the Precision Analysis

From the repository root:

```sh
python3 project/m2/tools/precision_analysis.py
```

The script writes `project/m2/sim/precision_analysis.json`. The numbers in
`project/m2/precision.md` are copied from that JSON output.

## Optional Synthesis Checks

These commands check that the RTL parses and maps through Yosys:

```sh
yosys -q -p "read_verilog -sv project/m2/rtl/compute_core.sv; synth -top compute_core"
yosys -q -p "read_verilog -sv project/m2/rtl/interface.sv; synth -top axis_interface"
```

## Deviations from M1

There are no interface deviations from M1: the selected protocol remains
AXI4-Stream. The M2 compute core is a compact 9-tap INT8 dot-product lane for
one 3x3 convolution window, not the full 128-MAC array planned for the final
accelerator. This keeps the M2 RTL small enough to verify directly while still
exercising the dominant profiled kernel.
