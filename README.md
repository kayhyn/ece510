# ECE 510 Spring 2026 -- HW4AI Project: 128-MAC INT8 Convolution Accelerator
## Kay Hynes

This repository contains a custom hardware accelerator for the **3x3 INT8
convolution** kernel that dominates YOLO-nano edge inference. The kernel was
profiled to be 95.6% of layer runtime and compute-bound (arithmetic intensity
~673 FLOP/byte), motivating a 128-lane INT8 multiply-accumulate array. The design
is synthesizable (OpenLane 2 / sky130), cycle-accurately verified end-to-end, and
benchmarked against the M1 software baseline.

## Milestone 4 submission (final)

The complete M4 deliverable package lives in **[`project/m4/`](project/m4/)**:

- **[`project/m4/README.md`](project/m4/README.md)** -- catalogs every M4 file
  and how to reproduce the results.
- **[`project/m4/report/design_justification.pdf`](project/m4/report/design_justification.pdf)**
  -- the 9-section design justification report (the basis for the final exam).

Measured headline result: the 128-MAC array sustains **127.861 of 128 MAC/cycle
(99.89%)** with **0 functional errors**, for a **10.96x (sign-off) to 20.89x
(typical)** speedup over the 160.9 ms/layer M1 NumPy baseline. RTL, testbench,
simulation log + waveform, OpenLane synthesis reports (timing/area/power), the
benchmark + measured roofline, and raw data are all under `project/m4/`.

## Repository layout

```
project/
  heilmeier.md          Heilmeier answers (post-profiling)
  m1/                   software baseline, roofline, interface selection
  m2/                   INT8 compute core + AXI4-Stream interface RTL, precision study
  m3/                   integrated single-lane top, co-simulation, synthesis
  m4/                   FINAL: 128-MAC array RTL, verification, synthesis, benchmark, report
codefest/               weekly codefest exercises
```
