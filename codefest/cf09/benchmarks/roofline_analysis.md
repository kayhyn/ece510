# CF09 Roofline Analysis (measured, post-M4)

The accelerator point is now **MEASURED** from the real OpenLane flow on the M4
128-MAC array, not projected. It lands at **51.7 GOPS (tt, 202 MHz)**, in a
**27.1 (ss) – 86.7 (ff) GOPS** corner band, versus the **projected 64 GOPS @
250 MHz**. The kernel still sits on the flat compute ceiling — its arithmetic
intensity (~673 FLOP/byte) is far right of every ridge — so the design is
compute-bound exactly as predicted; what changed is the *height* of the ceiling,
not the regime.

**Gap diagnosis.** The throughput-efficiency half of the projection was right
on: the streaming array measured **127.92 MAC/cycle (99.94% of 128)**, removing
the M3 single-lane 0.9-MAC/cycle restart bubble exactly as designed. The gap is
entirely **clock frequency**: 250 MHz was optimistic. The real placed-datapath
critical path is the **32-bit accumulate-adder carry chain** (starts at the
Stage-B product register), ~9.42 ns at the slow sign-off corner → ~106 MHz, and
~202 MHz typical; 250 MHz is reached only at the fast corner. Power also came in
~2× the linear projection (255 vs 133 mW) because each lane carries a full 32-bit
accumulator. The highest-leverage fixes to close the gap are (1) a carry-save /
retimed accumulator to lift Fmax toward 250 MHz, and (2) buffering/banking the
128-way broadcast nets so the full array reaches the single-lane datapath
ceiling (its pre-PNR STA is fanout-dominated). Both are listed in
`project/remaining_tasks.md`.
