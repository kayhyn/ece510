# ECE 510 Spring 2026 -- Tiled 128-MAC INT8 Convolution-Reduction Chiplet

This repository contains a custom SystemVerilog co-processor chiplet that
accelerates the 576-element INT8 reduction from a representative 3x3
convolution. The final synthesized production design uses a standard 64-bit
AXI4-Stream interface, 128 parallel INT8 MAC lanes, and 64-entry per-lane
weight storage. A host executes nine 64-element tiles and accumulates their
serialized INT32 partial results.

## Milestone 4 final submission

- [`project/m4/README.md`](project/m4/README.md) catalogs every final M4 file
  and provides reproduction commands.
- [`project/m4/report/design_justification.pdf`](project/m4/report/design_justification.pdf)
  is the required nine-section final report.
- [`project/m4/bench/benchmark.md`](project/m4/bench/benchmark.md) documents the
  final cycle-measured, timing-projected comparison and traceability.

The final testbench matches the synthesized `accel_top` configuration and
checks 9,216 tile partials plus 1,024 reconstructed full results with zero
errors. Combining the cycle-measured production schedule with the full-wrapper
setup-limited post-CTS frequency projection gives **9.335 GFLOP/s**,
**42.714 ms/layer**, and **3.77x projected chiplet-schedule speedup** over the
M1 160.9 ms NumPy baseline. The estimate excludes host-side sliding-window and
output processing. The full wrapper does not close timing and detailed routing did not
complete; the report documents those limitations and uses no sign-off claim.

## Repository layout

```text
project/
  heilmeier.md          M1 project framing
  m1/                   software baseline, interface selection, diagrams
  m2/                   initial core/interface simulation and precision study
  m3/                   first integrated design and synthesis attempt
  m4/                   final coherent production deliverable package
codefest/               weekly course exercises
```
