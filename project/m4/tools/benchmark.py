#!/usr/bin/env python3
"""Generate the final M4 production-chiplet benchmark and roofline.

The benchmark matches the synthesized accel_top configuration (L_MAX=64).
A complete 576-element convolution reduction is executed as nine 64-element
tiles. Cycle accounting includes weight loads, compute input beats, serialized
result beats, pipeline/host gaps, and the production wrapper's backpressure.
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
RAW_CSV_PATH = BENCH / "raw_measurements.csv"
ROOFLINE_PATH = BENCH / "roofline_final.png"

# Target workload: 52x52x64 -> 52x52x128, 3x3 INT8 convolution.
OUT_PIX = 52 * 52
CHANNELS = 128
FULL_L = 3 * 3 * 64
TILE_L = 64
NUM_TILES = FULL_L // TILE_L
LAYER_MACS = OUT_PIX * CHANNELS * FULL_L
LAYER_FLOPS = 2 * LAYER_MACS

# M1 baseline.
M1_TIME_S = 0.1609
M1_GFLOPS = LAYER_FLOPS / M1_TIME_S / 1e9
M1_RUNS_MS = [
    164.1, 164.5, 155.6, 164.3, 171.8, 161.3, 163.0, 151.0,
    149.0, 150.5, 160.7, 163.8, 144.6, 160.9, 150.6,
]

# Production transaction schedule. tb_top.sv validates the schedule using
# N_PIX=8 and measures 87,985 cycles:
#   73,728 weight + 4,608 compute + 9,216 drain + 6*72 gaps + 1 = 87,985.
WEIGHT_LOAD_BEATS = NUM_TILES * CHANNELS * TILE_L
COMPUTE_BEATS = NUM_TILES * OUT_PIX * TILE_L
DRAIN_BEATS = NUM_TILES * OUT_PIX * CHANNELS
TILE_PIXEL_GAP_CYCLES = 6
TILE_PIXELS = NUM_TILES * OUT_PIX
LAYER_CYCLES = (
    WEIGHT_LOAD_BEATS
    + COMPUTE_BEATS
    + DRAIN_BEATS
    + TILE_PIXEL_GAP_CYCLES * TILE_PIXELS
    + 1
)
SUSTAINED_MAC_PER_CYCLE = LAYER_MACS / LAYER_CYCLES

# Full accel_top post-CTS typical-corner result:
# 6.0 ns target + 2.730896 ns setup violation = 8.730896 ns.
ACCEL_PERIOD_NS = 6.0 + 2.730896475141717
ACCEL_FREQ_HZ = 1e9 / ACCEL_PERIOD_NS
ACCEL_POWER_W = 1.018  # full accel_top post-CTS, default switching activity

LAYER_TIME_S = LAYER_CYCLES / ACCEL_FREQ_HZ
ACCEL_GFLOPS = LAYER_FLOPS / LAYER_TIME_S / 1e9
SPEEDUP = M1_TIME_S / LAYER_TIME_S
ENERGY_MJ = ACCEL_POWER_W * LAYER_TIME_S * 1e3

# Two distinct arithmetic intensities:
# - algorithmic: ideal operand reuse, as calculated in M1
# - implemented-interface: actual 64-bit AXI4-Stream transaction bytes
ALGORITHM_BYTES = 173056 + 73728 + 346112
ALGORITHM_AI = LAYER_FLOPS / ALGORITHM_BYTES
INTERFACE_BYTES = 8 * (WEIGHT_LOAD_BEATS + COMPUTE_BEATS + DRAIN_BEATS)
INTERFACE_AI = LAYER_FLOPS / INTERFACE_BYTES
INTERFACE_BW_GBS = 8 * ACCEL_FREQ_HZ / 1e9


def main():
    BENCH.mkdir(parents=True, exist_ok=True)

    rows = [
        [
            "m1_software_baseline",
            "",
            "",
            "",
            "",
            f"{M1_TIME_S*1e3:.3f}",
            f"{M1_GFLOPS:.3f}",
            "1.00",
            "",
            "",
            f"{ALGORITHM_AI:.3f}",
            "measured software runtime",
            "not applicable",
        ],
        [
            "m4_production_accel_top_tiled",
            f"{ACCEL_FREQ_HZ/1e6:.3f}",
            str(LAYER_CYCLES),
            f"{SUSTAINED_MAC_PER_CYCLE:.3f}",
            str(INTERFACE_BYTES),
            f"{LAYER_TIME_S*1e3:.3f}",
            f"{ACCEL_GFLOPS:.3f}",
            f"{SPEEDUP:.2f}",
            f"{ACCEL_POWER_W:.3f}",
            f"{ENERGY_MJ:.3f}",
            f"{INTERFACE_AI:.3f}",
            "measured RTL cycle schedule; timing-projected performance",
            "full wrapper does not close timing; post-CTS setup-limited projection",
        ],
    ]

    with open(CSV_PATH, "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(
            [
                "config",
                "freq_MHz",
                "layer_cycles",
                "useful_MAC_per_total_cycle",
                "interface_bytes",
                "layer_time_ms",
                "throughput_GFLOPs",
                "speedup_vs_m1",
                "power_W",
                "energy_per_layer_mJ",
                "arithmetic_intensity_FLOP_per_byte",
                "measurement_status",
                "timing_status",
            ]
        )
        writer.writerows(rows)

    raw_rows = [
        ["simulation", "representative_pixels", 8, "tb_top.sv parameter"],
        ["simulation", "weight_load_beats", 73728, "final_run.log"],
        ["simulation", "compute_beats", 4608, "final_run.log"],
        ["simulation", "drain_beats", 9216, "final_run.log"],
        ["simulation", "backpressure_cycles", 3, "final_run.log; protocol test excluded from unstalled projection"],
        ["simulation", "unstalled_schedule_cycles", 87985, "final_run.log"],
        ["extrapolation", "output_pixels", OUT_PIX, "target workload"],
        ["extrapolation", "weight_load_beats", WEIGHT_LOAD_BEATS, "9*128*64"],
        ["extrapolation", "compute_beats", COMPUTE_BEATS, "9*2704*64"],
        ["extrapolation", "drain_beats", DRAIN_BEATS, "9*2704*128"],
        ["extrapolation", "pipeline_protocol_gap_cycles", TILE_PIXEL_GAP_CYCLES * TILE_PIXELS + 1, "6*9*2704+1"],
        ["extrapolation", "layer_cycles", LAYER_CYCLES, "sum of extrapolated categories"],
        ["timing", "clock_target_ns", 6.0, "config.json"],
        ["timing", "typical_setup_wns_ns", -2.730896475141717, "accel_postcts_wns.rpt"],
        ["timing", "setup_limited_period_ns", ACCEL_PERIOD_NS, "target minus WNS"],
        ["timing", "setup_limited_frequency_MHz", ACCEL_FREQ_HZ / 1e6, "projection; not timing-closed"],
    ]
    raw_rows.extend(
        ["m1_software", f"runtime_run_{i:02d}_ms", value, "sw_baseline.md"]
        for i, value in enumerate(M1_RUNS_MS, start=1)
    )
    with open(RAW_CSV_PATH, "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["source_group", "measurement", "value", "traceability"])
        writer.writerows(raw_rows)

    print(f"production layer cycles: {LAYER_CYCLES:,}")
    print(f"useful MAC/total cycle: {SUSTAINED_MAC_PER_CYCLE:.3f}")
    print(f"full accel_top setup-limited frequency projection: {ACCEL_FREQ_HZ/1e6:.3f} MHz")
    print(f"layer time: {LAYER_TIME_S*1e3:.3f} ms")
    print(f"throughput: {ACCEL_GFLOPS:.3f} GFLOP/s")
    print(f"speedup: {SPEEDUP:.2f}x")
    print(f"implemented-interface AI: {INTERFACE_AI:.3f} FLOP/byte")
    print(f"wrote {CSV_PATH}")
    print(f"wrote {RAW_CSV_PATH}")

    ai = np.logspace(-1, 3.2, 400)
    compute_ceiling = CHANNELS * 2 * ACCEL_FREQ_HZ / 1e9
    production_roof = np.minimum(INTERFACE_BW_GBS * ai, compute_ceiling)
    target_roof = np.minimum(32.0 * ai, 64.0)
    cpu_roof = np.minimum(200.0 * ai, 200.0)

    fig, ax = plt.subplots(figsize=(9, 6.5))
    ax.plot(
        ai,
        production_roof,
        color="#1f6fb2",
        lw=2.2,
        label=(
            f"Setup-limited projected accel_top roofline "
            f"({compute_ceiling:.1f} GFLOP/s compute, {INTERFACE_BW_GBS:.3f} GB/s stream)"
        ),
    )
    ax.plot(
        ai,
        target_roof,
        color="#1f6fb2",
        lw=1.3,
        ls="--",
        label="M1 target roofline (64 GFLOP/s, 32 GB/s ideal on-chip reuse)",
    )
    ax.plot(
        ai,
        cpu_roof,
        color="#888888",
        lw=1.5,
        ls="-.",
        label="M1 Pro reference roofline (200 GFLOP/s, 200 GB/s)",
    )

    ax.plot(
        [ALGORITHM_AI],
        [M1_GFLOPS],
        "s",
        color="#c0392b",
        ms=10,
        zorder=5,
        label=f"M1 software baseline ({M1_GFLOPS:.2f} GFLOP/s, algorithmic AI)",
    )
    ax.plot(
        [INTERFACE_AI],
        [ACCEL_GFLOPS],
        "o",
        color="#1f6fb2",
        ms=12,
        zorder=6,
        label=f"M4 accel_top projected ({ACCEL_GFLOPS:.2f} GFLOP/s, {SPEEDUP:.2f}x)",
    )
    ax.axvline(
        ALGORITHM_AI,
        color="#d9a400",
        ls=":",
        lw=1.2,
        label=f"Algorithmic AI = {ALGORITHM_AI:.1f} FLOP/byte",
    )
    ax.axvline(
        INTERFACE_AI,
        color="#16a085",
        ls=":",
        lw=1.2,
        label=f"Implemented-interface AI = {INTERFACE_AI:.1f} FLOP/byte",
    )

    ax.set_xscale("log")
    ax.set_yscale("log")
    ax.set_xlim(0.1, 1600)
    ax.set_ylim(0.5, 400)
    ax.set_xlabel("Arithmetic intensity (FLOP/byte)")
    ax.set_ylabel("Performance (GFLOP/s)")
    ax.set_title("M4 Final Roofline: synthesized 64-tap tiled production chiplet")
    ax.grid(True, which="both", ls=":", alpha=0.4)
    ax.legend(loc="lower right", fontsize=7.2)
    fig.tight_layout()
    fig.savefig(ROOFLINE_PATH, dpi=150)
    print(f"wrote {ROOFLINE_PATH}")


if __name__ == "__main__":
    main()
