# Remaining Tasks (post-M4, measurement-driven)

M4 built and measured the 128-MAC array (`project/m4/`). That closed three
earlier tasks: the array now exists, the per-lane pipeline is in, and the
streaming `first/last` control removed the M3 0.9-MAC/cycle restart bubble
(measured 127.92 MAC/cycle = 99.94% of 128). The remaining work below is ordered
by the real OpenLane measurements, not guesses.

## 1. Replace the 32-bit accumulate adder with a carry-save accumulator

The placed single-lane STA (run tag M4_LANE) shows the worst setup path starts
at the Stage-B product register `lane[0].bprod[15]` and propagates through the
**32-bit accumulate adder carry chain** (`acc + prod_ext`): ~9.42 ns at the slow
corner → ~106 MHz, vs the 250 MHz target. Keep the running sum in redundant
(sum, carry) form across the L reduction elements and do a single
carry-propagate add only on `in_last`. This removes the per-cycle 32-bit carry
propagation from the inner loop and is the direct lever to raise Fmax from
~106 MHz (ss) toward the 250 MHz design point. Expected to also shrink
sequential power.

## 2. Pipeline/bank the broadcast nets and wrap the array I/O for real full-array PnR

Pre-PNR STA of the full array (run tag M4_SYNTH) is dominated by the unbuffered
broadcast control net `b_valid` at **fanout 5,881** (a single inverter shows a
333.7 ns delay), and the bare module exposes **5,134 top-level pins**, which
blocked floorplan IO placement. Fix both: (a) add a 1-deep register fan-out tree
that rebroadcasts `activation`/`valid`/`first`/`last` into banks of ~16 lanes so
no net drives more than ~16+1 sinks; (b) wrap the array with on-chip weight SRAM
(72 KB) feeding the per-lane weight ports and an output buffer draining
`results`, so the synthesized block has a realistic pin count instead of 5,134
chip pins. This is the prerequisite to push the full 128-lane array through
place-and-route and obtain a true full-array Fmax rather than the single-lane
datapath ceiling.

## 3. Re-run signoff with activity-annotated power and a routed netlist

Current power (255 mW tt / 343 mW ff) is OpenLane **pre-PNR with default
switching activity** — it omits the clock tree and uses generic toggle rates.
After tasks 1–2, run the full flow through detailed routing and re-estimate
power with a SAIF/VCD captured from the `tb_mac_array` streaming workload (128
always-active lanes), so the CF09 energy-efficiency number (~203 GOPS/W tt) is
backed by routed parasitics and real activity rather than the current
pre-route/default-activity estimate.
