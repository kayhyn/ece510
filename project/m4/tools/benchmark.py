#!/usr/bin/env python3
"""M4 benchmark: derive accelerator throughput/energy from the measured
simulation cycle count + the OpenLane post-synthesis frequencies, compare to the
M1 software baseline, write benchmark_data.csv, and render roofline_final.png.

Every number below traces to a committed source file:
  - M1 software baseline:  project/m1/sw_baseline.md
  - measured MAC/cycle:    project/m4/sim/final_run.log
  - post-synth frequency:  project/m4/synth/timing_report.txt (placed lane)
  - power per corner:      project/m4/synth/power_report.txt
"""

from pathlib import Path
import csv

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

ROOT = Path(__file__).resolve().parents[3]
BENCH = ROOT / "project" / "m4" / "bench"
CSV_PATH = BENCH / "benchmark_data.csv"
ROOFLINE_PATH = BENCH / "roofline_final.png"

# ---- Workload (dominant 3x3 INT8 conv, 52x52x64 -> 52x52x128) -------------
OUT_PIX = 52 * 52            # 2704 output spatial pixels
CHANNELS = 128               # output channels (= NUM_MAC lanes)
L = 3 * 3 * 64               # 576 reduction elements per pixel
LAYER_MACS = OUT_PIX * CHANNELS * L          # 199,360,512
LAYER_FLOPS = 2 * LAYER_MACS                 # 398,721,024 (2 FLOP / MAC)

# ---- M1 software baseline (project/m1/sw_baseline.md) ---------------------
M1_TIME_S = 0.1609           # median of 15 runs, seconds
M1_GFLOPS = LAYER_FLOPS / M1_TIME_S / 1e9    # ~2.48 GFLOP/s
M1_POWER_W = 15.0            # assumed M1 Pro CPU active power (see benchmark.md)

# ---- M4 measured simulation result (project/m4/sim/final_run.log) ---------
SIM_MACS = 589824
SIM_CYCLES = 4613
SUSTAINED_MAC_PER_CYC = SIM_MACS / SIM_CYCLES   # 127.861

# Full-layer cycle count at the measured sustained rate.
LAYER_CYCLES = LAYER_MACS / SUSTAINED_MAC_PER_CYC

# ---- Post-synthesis frequencies (placed-and-routed single lane with the
# carry-save accumulator, timing_report.txt section B; run tag M4_CSA_LANE) ---
# Per-lane post-PnR power scaled by 128 lanes (see power_report.txt section B).
# corner: (freq_Hz, power_W per array)
CORNERS = {
    "ss_signoff_113MHz": (113.21e6, 0.36308),   # 4.0 + 4.833 ns -> 8.833 ns / lane 2.836 mW * 128
    "tt_typical_215MHz": (214.92e6, 0.45984),   # 4.0 + 0.653 ns -> 4.653 ns / lane 3.592 mW * 128
    "ff_fast_333MHz":    (332.74e6, 0.45984),   # 4.0 - 0.995 ns -> 3.005 ns (re-use tt power as upper bound)
    "target_250MHz":     (250.00e6, 0.45984),   # M1 design target (not met at signoff)
}

# ---- On-chip / interface bandwidths for the roofline ----------------------
ACC_BW_GBs = 32.0            # on-chip SRAM/line-buffer bandwidth (heilmeier.md)
CPU_PEAK_GFLOPS = 200.0      # M1 Pro FP32 NEON peak (sw_baseline.md)
CPU_BW_GBs = 200.0           # M1 Pro DRAM BW -> ridge ~1.0 FLOP/B
KERNEL_AI = LAYER_FLOPS / (173056 + 73728 + 346112)  # ~672.5 FLOP/byte


def main():
    BENCH.mkdir(parents=True, exist_ok=True)
    rows = []
    print(f"Layer: {LAYER_MACS:,} MACs ({LAYER_FLOPS:,} FLOP), AI={KERNEL_AI:.1f} FLOP/B")
    print(f"M1 baseline: {M1_TIME_S*1e3:.1f} ms -> {M1_GFLOPS:.2f} GFLOP/s")
    print(f"Sustained: {SUSTAINED_MAC_PER_CYC:.3f} MAC/cycle, "
          f"layer_cycles={LAYER_CYCLES:,.0f}\n")

    rows.append(["m1_software_baseline", "", f"{M1_TIME_S*1e3:.1f}",
                 f"{M1_GFLOPS:.3f}", "1.00", f"{M1_POWER_W:.3f}",
                 f"{M1_POWER_W*M1_TIME_S*1e3:.2f}", f"{M1_GFLOPS/M1_POWER_W:.3f}"])

    for name, (freq, power) in CORNERS.items():
        t_s = LAYER_CYCLES / freq
        gflops = LAYER_FLOPS / t_s / 1e9
        speedup = M1_TIME_S / t_s
        energy_mj = power * t_s * 1e3
        gops_per_w = gflops / power
        rows.append([f"m4_accel_{name}", f"{freq/1e6:.2f}", f"{t_s*1e3:.3f}",
                     f"{gflops:.3f}", f"{speedup:.2f}", f"{power:.3f}",
                     f"{energy_mj:.3f}", f"{gops_per_w:.2f}"])
        print(f"  {name:22s} {freq/1e6:6.1f} MHz  {t_s*1e3:7.3f} ms  "
              f"{gflops:6.2f} GFLOP/s  {speedup:5.2f}x  "
              f"{energy_mj:6.3f} mJ  {gops_per_w:6.1f} GFLOP/s/W")

    with open(CSV_PATH, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["config", "freq_MHz", "layer_time_ms", "throughput_GFLOPs",
                    "speedup_vs_m1", "power_W", "energy_per_layer_mJ",
                    "energy_efficiency_GFLOPs_per_W"])
        w.writerows(rows)
    print(f"\nwrote {CSV_PATH}")

    # ---------------- Roofline plot ----------------
    fig, ax = plt.subplots(figsize=(9, 6.5))
    ai = np.logspace(-1, 3.2, 400)

    # Accelerator roofline (measured tt ceiling + target ceiling).
    acc_peak_tt = SUSTAINED_MAC_PER_CYC * 2 * 214.92e6 / 1e9   # measured tt
    acc_peak_target = CHANNELS * 2 * 250e6 / 1e9               # 64 GFLOP/s target
    acc_roof_tt = np.minimum(ACC_BW_GBs * ai, acc_peak_tt)
    ax.plot(ai, acc_roof_tt, color="#1f6fb2", lw=2.2,
            label=f"Accelerator roofline (measured tt: {acc_peak_tt:.0f} GFLOP/s peak,"
                  f" {ACC_BW_GBs:.0f} GB/s)")
    ax.axhline(acc_peak_target, color="#1f6fb2", lw=1.3, ls="--",
               label=f"Accelerator target ceiling ({acc_peak_target:.0f} GFLOP/s @250MHz)")

    # CPU (M1 Pro) roofline for context.
    cpu_roof = np.minimum(CPU_BW_GBs * ai, CPU_PEAK_GFLOPS)
    ax.plot(ai, cpu_roof, color="#888888", lw=1.6, ls="-.",
            label=f"M1 Pro CPU roofline ({CPU_PEAK_GFLOPS:.0f} GFLOP/s, {CPU_BW_GBs:.0f} GB/s)")

    # Kernel arithmetic intensity line.
    ax.axvline(KERNEL_AI, color="#d9a400", ls=":", lw=1.4,
               label=f"Kernel AI = {KERNEL_AI:.0f} FLOP/byte (compute-bound)")

    # Points.
    ax.plot([KERNEL_AI], [M1_GFLOPS], "s", color="#c0392b", ms=11, zorder=5,
            label=f"M1 software baseline ({M1_GFLOPS:.2f} GFLOP/s)")
    acc_meas_tt = SUSTAINED_MAC_PER_CYC * 2 * 214.92e6 / 1e9
    acc_meas_ss = SUSTAINED_MAC_PER_CYC * 2 * 113.21e6 / 1e9
    ax.plot([KERNEL_AI], [acc_meas_tt], "o", color="#1f6fb2", ms=12, zorder=6,
            label=f"M4 accelerator MEASURED (tt {acc_meas_tt:.1f} GFLOP/s)")
    ax.plot([KERNEL_AI], [acc_meas_ss], "v", color="#16a085", ms=10, zorder=6,
            label=f"M4 accelerator MEASURED (ss {acc_meas_ss:.1f} GFLOP/s)")
    # Speedup arrow.
    ax.annotate("", xy=(KERNEL_AI, acc_meas_tt), xytext=(KERNEL_AI, M1_GFLOPS),
                arrowprops=dict(arrowstyle="->", color="#444", lw=1.6))
    ax.text(KERNEL_AI * 1.15, np.sqrt(M1_GFLOPS * acc_meas_tt),
            f"{acc_meas_tt/M1_GFLOPS:.1f}x\n(tt)", fontsize=10, color="#444")

    ax.set_xscale("log")
    ax.set_yscale("log")
    ax.set_xlim(0.1, 1600)
    ax.set_ylim(0.5, 400)
    ax.set_xlabel("Arithmetic intensity (FLOP/byte)")
    ax.set_ylabel("Performance (GFLOP/s)")
    ax.set_title("M4 Roofline: 3x3 INT8 conv kernel, software baseline vs. "
                 "measured accelerator")
    ax.grid(True, which="both", ls=":", alpha=0.4)
    ax.legend(loc="lower right", fontsize=7.6)
    fig.tight_layout()
    fig.savefig(ROOFLINE_PATH, dpi=150)
    print(f"wrote {ROOFLINE_PATH}")


if __name__ == "__main__":
    main()
