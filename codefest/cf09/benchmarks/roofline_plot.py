"""
CF09 Task 9 -- Accelerator on the roofline (measured SW + MEASURED M4 HW).
=========================================================================
Reuses the CF09 part-1 arithmetic intensity (operating point AI ~= 673
FLOP/byte, perfect-weight-reuse upper bound) and plots:

  * M1 Pro CPU baseline roofline + MEASURED SW point (4.21 GFLOP/s)
  * sky130 INT8 MAC-array accelerator roofline (projected 64 GOPS ceiling for
    reference) + MEASURED M4 points from the real OpenLane flow:
      tt 51.7 GOPS, ss 27.1 GOPS, ff 86.7 GOPS
    (throughput = 2 x 127.92 MAC/cycle [measured] x placed datapath Fmax
    [measured]; see benchmarks/benchmark_results.md).

Saves roofline_plot.png.
"""

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

# --- ceilings ---
accel_peak_proj = 64.0    # GOPS  (PROJECTED: 128 MACs * 2 op * 250 MHz)
accel_bw        = 32.0    # GB/s  on-chip line-buffer / weight-SRAM bandwidth
cpu_peak        = 200.0   # GFLOP/s (M1 Pro FP32 NEON)
cpu_bw          = 200.0   # GB/s   LPDDR5 unified memory

# --- operating-point AI (CF09 part 1, perfect-weight-reuse upper bound) ---
ai_op = 672.5        # FLOP/byte

# --- data points ---
sw_measured = 4.21    # GFLOP/s  (MEASURED, run_sw_baseline.py median)
m4_tt = 51.7          # GOPS  MEASURED, 2 x 127.92 MAC/cyc x 202 MHz (tt)
m4_ss = 27.1          # GOPS  MEASURED, slow sign-off corner (106 MHz)
m4_ff = 86.7          # GOPS  MEASURED, fast corner (339 MHz)

fig, ax = plt.subplots(figsize=(11, 7))
ai = np.logspace(-1, 4, 600)

# projected 64 GOPS ceiling (reference, dashed) + measured tt ceiling (solid)
ax.plot(ai, np.minimum(accel_peak_proj, accel_bw * ai), "r--", lw=1.8, alpha=0.7,
        label=f"sky130 accel ceiling, PROJECTED ({accel_peak_proj:.0f} GOPS @250MHz)")
ax.plot(ai, np.minimum(m4_tt, accel_bw * ai), "r-", lw=2.5,
        label=f"sky130 accel ceiling, MEASURED tt ({m4_tt:.0f} GOPS @202MHz)")
ax.plot(ai, np.minimum(cpu_peak, cpu_bw * ai), "b-", lw=2.0,
        label=f"M1 Pro CPU roofline ({cpu_peak:.0f} GFLOP/s, {cpu_bw:.0f} GB/s)")

# operating-point AI marker
ax.axvline(ai_op, color="purple", ls="--", lw=1.6, alpha=0.7)
ax.text(ai_op * 0.92, 0.55, "operating AI\n~673 FLOP/B\n(weight reuse)",
        color="purple", fontsize=8.5, ha="right", fontweight="bold")

# measured SW point
ax.plot(ai_op, sw_measured, "bo", ms=13, zorder=6)
ax.annotate("SW baseline (MEASURED)\n4.21 GFLOP/s\n(~2% of CPU peak)",
            xy=(ai_op, sw_measured), xytext=(ai_op * 0.03, sw_measured * 0.9),
            fontsize=9, fontweight="bold", color="blue",
            arrowprops=dict(arrowstyle="->", color="blue", lw=1.4),
            bbox=dict(boxstyle="round,pad=0.3", fc="lightyellow", ec="blue"))

# projected ceiling marker (reference)
ax.plot(ai_op, accel_peak_proj, "r^", ms=12, mfc="none", mew=1.8, zorder=5)
ax.annotate("PROJECTED 64 GOPS\n@250 MHz (optimistic)",
            xy=(ai_op, accel_peak_proj), xytext=(ai_op * 0.02, accel_peak_proj * 1.4),
            fontsize=8.5, color="darkred", alpha=0.85,
            arrowprops=dict(arrowstyle="->", color="darkred", lw=1.0, alpha=0.6))

# measured M4 points (tt primary, ss/ff range)
ax.plot([ai_op, ai_op, ai_op], [m4_ss, m4_tt, m4_ff], "r|", ms=18, mew=2, zorder=6)
ax.plot(ai_op, m4_tt, "rs", ms=13, zorder=7)
ax.annotate("M4 array (MEASURED)\ntt 51.7 GOPS @202 MHz\n[ss 27.1 .. ff 86.7]",
            xy=(ai_op, m4_tt), xytext=(ai_op * 0.025, m4_tt * 0.30),
            fontsize=9, fontweight="bold", color="darkred",
            arrowprops=dict(arrowstyle="->", color="darkred", lw=1.5),
            bbox=dict(boxstyle="round,pad=0.3", fc="mistyrose", ec="darkred"))

ax.set_xscale("log")
ax.set_yscale("log")
ax.set_xlabel("Arithmetic Intensity (FLOP / byte)", fontsize=12)
ax.set_ylabel("Attainable Performance (GOPS or GFLOP/s)", fontsize=12)
ax.set_title("CF09 Roofline -- SW baseline (measured) vs M4 128-MAC array (MEASURED)\n"
             "3x3 INT8 conv 52x52x64->128, operating AI ~673 FLOP/byte",
             fontsize=12, fontweight="bold")
ax.legend(loc="lower right", fontsize=8.5)
ax.set_xlim(0.1, 10000)
ax.set_ylim(0.1, 500)
ax.grid(True, which="both", alpha=0.3)

plt.tight_layout()
plt.savefig("roofline_plot.png", dpi=150, bbox_inches="tight")
print("Saved roofline_plot.png")
