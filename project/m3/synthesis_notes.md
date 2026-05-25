# M3 Synthesis Notes and Scope Status

Milestone 3 integrated the M2 AXI4-Stream interface module with the M2 INT8
compute core and pushed the integrated design through OpenLane 2 far enough to
obtain mapped synthesis, pre-PNR timing, area, and power reports. The new
`top` module instantiates `axis_interface` and `compute_core` directly. The
glue logic observes accepted host write transactions on the AXI4-Stream input,
decodes a small command field in the M2 interface payload, loads the nine
activation taps, loads the nine weight taps, loads the 32-bit bias in two
16-bit writes, pulses the compute-core start input, latches the compute result,
and returns a one-word result response on the host-facing AXI4-Stream output.
The testbench does not drive the compute core directly. It only uses host-side
stream writes and reads, which preserves the end-to-end interface requirement.

The exercised workload is the same representative 3x3 INT8 convolution lane
used in M2. That is a scoped version of the M1 dominant kernel, where the
baseline profiled a 52x52x64 input, a 3x3x64x128 convolution, INT8 operands,
and INT32 accumulation. The current RTL does not implement the full planned
128-MAC array or the complete 64-channel convolution layer. It implements one
9-tap dot-product lane, which keeps the RTL small enough to inspect and verify
while still exercising the central operation in the dominant kernel: signed
INT8 multiply-accumulate into an INT32 result. This is the same scope already
declared in M2, so there is no new algorithmic scope reduction in M3. The M4
benchmark will remain meaningful by scaling this lane model toward additional
lanes or by reporting per-lane throughput, area, and power relative to the M1
software baseline.

The end-to-end co-simulation passed with Icarus Verilog. The testbench sends 21
host commands: nine activation writes, nine weight writes, two bias writes, one
start write, and one read-result write after the core completes. The independent
software-style reference inside the testbench computes the expected dot product
from the signed activation and weight arrays plus the bias. For the committed
vector, the expected result is -110. The host receives response word
`bfffff92`, where the high nibble marks an M3 result response and the lower 28
bits encode the sign-extended result. The committed log prints one unambiguous
`PASS: m3 end-to-end cosim` line, and the waveform image marks the host write
phase, internal compute activity, and host readback phase.

OpenLane 2 v2.3.10 was run from the supported Nix tool environment inside the
container. The command used for the committed report run was
`openlane --run-tag M3_SYNTH --overwrite --to OpenROAD.STAPrePNR
project/m3/synth/config.json`. I intentionally stopped at `OpenROAD.STAPrePNR`
because the M3 checklist asks for synthesis, timing, area, power, and critical
path information, not full detailed routing closure. A full exploratory run did
continue into detailed routing, but TritonRoute was slow and unnecessary for
this milestone. The successful `M3_SYNTH` run completed with exit code 0 and is
captured in `openlane_run.log`.

The integrated RTL synthesized successfully. Yosys/OpenLane reported zero
unmapped instances, zero synthesis check errors, zero inferred latches, and
zero lint errors. There are 444 lint warnings, mostly width and style warnings
from the compact SystemVerilog used for packed arrays and command fields, but
they did not block synthesis. The mapped Sky130 HD netlist contains 2000 cells
and has a reported top-level cell area of 23129.683200 square micrometers.
Sequential cells account for 6891.609600 square micrometers, or 29.80% of the
mapped cell area. Major cell contributors include 324 `dfxtp_2` flip-flops, 207
`and2_2` cells, 175 `mux2_1` cells, 172 `nor2_2` cells, and 162 `xnor2_2`
cells. This distribution is consistent with a small registered interface around
a multiply/accumulate datapath.

Timing is partially successful. At the requested 10.0 ns clock period, the
typical and fast pre-PNR corners meet setup timing: `nom_tt_025C_1v80` has
+1.4822 ns setup slack, and `nom_ff_n40C_1v95` has +4.6752 ns setup slack. Hold
timing is clean in all reported corners, with overall hold TNS of 0 and no hold
violations. The slow corner `nom_ss_100C_1v60` fails setup with -6.4845 ns WNS,
-163.3642 ns TNS, and 44 setup-violating paths. The worst path starts at
flip-flop `_3577_`, whose named net is `compute_i.tap_index[0]`, and ends at
flip-flop `_3637_`. The path runs through the compute core's packed tap
selection and signed multiply/accumulate logic, not through the AXI interface
glue. This identifies the next RTL target clearly: pipeline the selected
activation and weight before multiplication, then pipeline the product before
the accumulator.

Power estimation was also attempted and produced pre-PNR numbers. The final
metrics report total power of approximately 1.569 mW across the OpenLane
corners. In the slow-corner `nom_ss_100C_1v60` power report, total power is
1.039114 mW, with 1.008537 mW internal, 0.016990 mW switching, and 0.013587 mW
leakage. These are useful early estimates, but they use OpenLane's default
activity assumptions rather than activity annotated from the M3 testbench VCD.
For M4, the power flow should be rerun with realistic switching activity from
the host-programmed dot-product workload.

The main M4 work is therefore clear. Functionally, the host-to-interface-to-core
path works. Structurally, OpenLane maps the design into Sky130 cells and reports
area and power. The remaining design risk is slow-corner setup timing in the
compute datapath. The smallest meaningful RTL change is to pipeline the
compute-core tap-select, multiplier, and accumulator path while keeping the
AXI4-Stream command protocol unchanged. That preserves the M3 software-visible
behavior and directly attacks the reported critical path.
