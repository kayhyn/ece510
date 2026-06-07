# M4 Accelerator -- Next Steps (Agent Handoff)

This file is a self-contained brief for an engineer/agent who is picking up the
project cold. It captures the current state, the open problems, and the concrete
work to finish a *true* full-array place-and-routed accelerator. Read this top to
bottom before changing anything.

## 0. Context in one paragraph

The project is a custom hardware accelerator for the **3x3 INT8 convolution**
that dominates YOLO-nano (95.6% of layer runtime; arithmetic intensity ~673
FLOP/byte, compute-bound). The design is a **128-lane INT8 MAC array**,
output-stationary / weight-streaming, 3-stage pipeline, with `valid/first/last`
streaming control. M4 is **already submitted and git-tagged `m4-submission`** --
do NOT amend that tag. All work below is post-submission hardening and goes in
NEW commits.

## 1. Current state (what is DONE and verified)

- **RTL** (`project/m4/rtl/`):
  - `mac_array.sv` -- the authoritative 128-lane compute core (synthesized +
    benchmarked). Do not change its logic without re-running synthesis.
  - `compute_core.sv` -- transparent wrapper of `mac_array`.
  - `interface.sv` (`stream_if`) -- AXI4-Stream interface; **currently exposes
    the full-width `s_weights[1023:0]` and `m_results[4095:0]` buses** (this is
    the thing to fix, see Task 1).
  - `top.sv` -- integration: `stream_if` + `compute_core`.
- **Verification** (`project/m4/tb/tb_top.sv`, `project/m4/sim/`):
  - `final_run.log`: **PASS, 0 errors, 127.861 MAC/cycle (99.89% of 128)**.
  - `final_waveform.png`: annotated end-to-end transaction.
  - Reproduce (from repo root):
    ```sh
    iverilog -g2012 -Wall -o /tmp/tb.vvp \
      project/m4/rtl/mac_array.sv project/m4/rtl/compute_core.sv \
      project/m4/rtl/interface.sv project/m4/rtl/top.sv project/m4/tb/tb_top.sv
    vvp /tmp/tb.vvp                                    # expect PASS
    python3 project/m4/tools/generate_waveform.py      # -> sim/final_waveform.png
    ```
- **Synthesis** (`project/m4/synth/`, OpenLane 2 v2.3.10, sky130_fd_sc_hd):
  - Area: **99,710 cells, 1,065,403 um^2**. Power: **193/255/343 mW** (ss/tt/ff,
    pre-PNR, default activity). Fmax from placed single lane: **106 MHz (ss) /
    202 MHz (tt) / 339 MHz (ff)**; 250 MHz target NOT met at sign-off.
- **Benchmark** (`project/m4/bench/`): measured **10.96x (ss) - 20.89x (tt)**
  speedup vs the 160.9 ms M1 baseline; `benchmark_data.csv` + `roofline_final.png`.
  Regenerate with `python3 project/m4/tools/benchmark.py`.
- **Report**: `project/m4/report/design_justification.pdf` (9 sections, ~2,700
  words). Source `design_justification.md`; rebuild with
  `pandoc design_justification.md -o design_justification.pdf --pdf-engine=xelatex`
  (needs `PATH=/Library/TeX/texbin:$PATH`).

## 2. The three open problems (root causes, measured)

1. **Full 128-lane array will not place-and-route standalone.** Synthesizing
   `mac_array` (or current `top`) exposes ~5,134 chip pins (`weights` 1024 +
   `results` 4096 + control), and OpenLane's perimeter pin placer fails
   (PPL-0024). This is an **I/O-packaging artifact, not a logic/timing limit** --
   in a real chip those operands are internal (on-chip SRAM + result buffer).
2. **Broadcast nets have catastrophic fan-out.** The shared `b_valid` /
   activation / first / last nets drive all 128 lanes (fanout ~5,881), giving the
   meaningless pre-PNR -387 ns WNS. CTS/buffering fixes most of it, but it must be
   architecturally banked to scale.
3. **The 32-bit ripple-carry accumulate adder is the datapath critical path.**
   This is why the placed lane closes at only ~106 MHz (ss) instead of 250 MHz.

Tasks 1-3 below fix these in priority order. (1) is the prerequisite for any
real full-array PnR; (2) and (3) then determine the real full-array Fmax/power.

## 3. Task 1 -- Wrap the array for realistic I/O (PRIORITY: unblocks PnR)

Goal: turn the ~5,134-pin block into a ~100-150-pin block that floorplans and
routes. Make the wide weight/result buses **internal**. Create a new top, e.g.
`rtl/accel_top.sv`, do NOT edit `mac_array.sv`.

Concrete sub-steps:
- **Weight memory.** Replace the 1024-bit `s_weights` port with an internal
  weight bank: 128 lanes x L=576 x 8b = 72 KB. For the educational sky130 flow,
  either instantiate a sky130 SRAM macro (via OpenLane macro flow) or infer a
  registered/BRAM-style bank. Weights are written once over the input stream
  (a `LOAD_WEIGHT {addr, byte}` opcode) and reused across all pixels.
- **Result serializer.** Replace the 4096-bit parallel `m_results` with an
  output FSM that drains the 128 channel results over the output AXI4-Stream a
  few channels per beat (e.g., 1x32b or 2x32b per beat). Costs ~64-128 drain
  cycles per pixel -- negligible vs the 576-cycle reduction.
- **Narrow streaming ports.** External ports become a real AXI4-Stream width:
  `s_tdata[63:0]` (opcode-tagged: weight-load vs activation-stream) and
  `m_tdata[63:0]`. Resulting top-level pin count ~140.
- **Verify**: extend `tb_top.sv` (or add `tb_accel_top.sv`) to (a) stream the
  weight-load phase, (b) stream activations, (c) collect serialized results, and
  check against the same independent golden reference. Must still report
  `errors=0` and ~128 MAC/cycle during the compute phase.
- **Synthesis**: add `synth/config_accel.json` pointing `DESIGN_NAME` at
  `accel_top`, then run the **full flow** (not just `--to OpenROAD.STAPrePNR`):
  ```sh
  docker run --rm -v "$PWD":/work -v "$HOME/.volare":/root/.volare \
    -e PDK_ROOT=/root/.volare -w /work ghcr.io/efabless/openlane2:2.3.10 \
    openlane --run-tag M4_ACCEL --overwrite /work/project/m4/synth/config_accel.json
  ```
  Acceptance: `Flow complete.` through detailed routing, a real `metrics.json`,
  and a routed timing report (a true full-array Fmax, not the single-lane proxy).

## 4. Task 2 -- Bank the broadcast nets

After Task 1, the broadcast control/activation still fans out to 128 sinks. Add a
**1-deep registered fan-out tree**: rebroadcast `activation`/`valid`/`first`/
`last` into banks of ~16 lanes so no net drives more than ~16-17 sinks. This adds
1 cycle of latency (adjust the `first/last` pipeline depth and the tb's drain
loop accordingly; throughput is unaffected). Re-verify `errors=0`, then re-run
the Task-1 flow and confirm the broadcast path is no longer the worst net.

## 5. Task 3 -- Carry-save accumulator (raise Fmax)

The worst datapath path is `acc + prod_ext` (32-bit ripple carry). Replace the
per-cycle full add with a **carry-save accumulator**: keep the running sum in
redundant (sum, carry) form across the L reduction elements and do a single
carry-propagate add only on `in_last`. Expected to lift the slow-corner Fmax from
~106 MHz toward the 202+ MHz range and reduce sequential power. This DOES change
`mac_array.sv` logic, so: re-run the iverilog test (`errors=0`, MAC/cycle
unchanged), then re-run synthesis and update `synth/timing_report.txt`,
`area_report.txt`, `power_report.txt`, `synthesis_notes.md`, and the benchmark.

## 6. Task 4 -- Activity-annotated, post-route power

Current power is pre-PNR with default switching activity. After Tasks 1-3:
- Generate a SAIF/VCD from the `tb_top` streaming workload (128 active lanes).
- Re-run OpenROAD power with the routed netlist + annotated activity.
- Update `power_report.txt` and the energy rows in `bench/benchmark_data.csv` /
  `benchmark.md` / report Section 8, replacing the "pre-PNR / default-activity"
  caveat with the real number.

## 7. Rules / guardrails

- **Never amend or move the `m4-submission` tag.** All work goes in new commits.
- Keep claims and code in sync: if you change the dataflow, pipeline depth, lane
  count, or numbers, update `report/design_justification.md` AND rebuild the PDF,
  AND update `bench/*` so every reported number still traces to a committed file.
- Re-run the iverilog testbench after every RTL change; `errors=0` is the gate.
- Regeneration scripts live in `project/m4/tools/` (`generate_waveform.py`,
  `benchmark.py`, `figures.py`) -- re-run them so artifacts stay consistent.
- Build artifacts (`*.vvp`) are gitignored; don't commit them.
- Toolchain available on this machine: `iverilog`/`vvp`, `python3` + matplotlib +
  numpy + pypdf, `pandoc` + `xelatex`/`pdflatex` (`/Library/TeX/texbin`),
  `wkhtmltopdf`, `pdftotext`. OpenLane 2 runs via colima/docker (see m4 README).

## 8. Definition of done (full hardening)

- `accel_top` (or equivalent) routes cleanly in OpenLane through detailed routing
  with a realistic pin count, producing a **routed full-array** timing/area/power.
- Broadcast fan-out and the 32-bit adder are no longer the limiters; slow-corner
  Fmax is reported from the routed design.
- Power is activity-annotated post-route; benchmark + report updated to match.
- Functional sim still PASSes with `errors=0`; every number in the report and
  benchmark traces to a committed file; the report still has 9 distinct sections
  and stays within 2,000-5,000 words.
