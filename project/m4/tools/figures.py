#!/usr/bin/env python3
"""Render the architecture block diagram and the dataflow diagram for the M4
design justification report, and copy the roofline + waveform into figures/."""

import shutil
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

ROOT = Path(__file__).resolve().parents[3]
FIGS = ROOT / "project" / "m4" / "report" / "figures"
BENCH = ROOT / "project" / "m4" / "bench"
SIM = ROOT / "project" / "m4" / "sim"


def box(ax, x, y, w, h, text, fc, ec="#333", fs=9):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.02,rounding_size=0.06",
                                fc=fc, ec=ec, lw=1.4))
    ax.text(x + w / 2, y + h / 2, text, ha="center", va="center", fontsize=fs)


def arrow(ax, x0, y0, x1, y1, text=None, color="#222", fs=8):
    ax.add_patch(FancyArrowPatch((x0, y0), (x1, y1), arrowstyle="-|>",
                                 mutation_scale=14, color=color, lw=1.5))
    if text:
        ax.text((x0 + x1) / 2, (y0 + y1) / 2 + 0.12, text, ha="center",
                va="bottom", fontsize=fs, color=color)


def block_diagram():
    fig, ax = plt.subplots(figsize=(11, 5.6))
    ax.set_xlim(0, 12)
    ax.set_ylim(0, 7)
    ax.axis("off")

    box(ax, 0.2, 3.0, 1.7, 1.2, "Host\n(FPGA SoC\nARM core)", "#eef3fb")
    box(ax, 2.4, 2.4, 2.5, 2.4, "accel_top\n64-bit AXI4-Stream\nopcode decoder +\nresult serializer", "#fdf2e0")

    # Compute core box containing lanes.
    box(ax, 5.6, 0.6, 5.9, 5.9, "", "#f2faf2", ec="#2a8")
    ax.text(8.55, 6.15, "64-tap tiled production chiplet (128 lanes, output-stationary)",
            ha="center", fontsize=10, weight="bold")
    for k, yy in enumerate([4.8, 3.9, 3.0]):
        box(ax, 6.0, yy, 5.1, 0.7,
            f"lane {k}: 64xINT8 weights | 8x8 mul | INT32 CSA",
            "#ffffff", fs=8)
    ax.text(8.55, 2.5, ". . .  (128 lanes total)", ha="center", fontsize=9)
    box(ax, 6.0, 1.0, 5.1, 0.7, "registered broadcast + 128-channel partial-result buffer",
        "#eaf6ff", fs=8)

    arrow(ax, 1.9, 3.8, 2.4, 3.8, "64b load/compute")
    arrow(ax, 4.9, 4.15, 6.0, 4.15, "activation +\nweight-bank reads")
    # results return arrow (compute core -> interface)
    ax.add_patch(FancyArrowPatch((6.0, 1.35), (4.9, 3.1), arrowstyle="-|>",
                                 mutation_scale=14, color="#b5651d", lw=1.5,
                                 connectionstyle="arc3,rad=-0.25"))
    ax.text(5.0, 2.0, "128 partials\nserialized", ha="center", fontsize=8, color="#b5651d")
    arrow(ax, 2.4, 3.0, 1.9, 3.0, "64b partials")

    ax.set_title("Figure 2. Final production architecture: host-managed nine-tile "
                 "reduction through synthesized accel_top", fontsize=11)
    fig.tight_layout()
    fig.savefig(FIGS / "fig2_block_diagram.png", dpi=150)
    plt.close(fig)


def dataflow_diagram():
    fig, ax = plt.subplots(figsize=(11, 5.6))
    ax.set_xlim(0, 12)
    ax.set_ylim(0, 7)
    ax.axis("off")

    ax.text(6, 6.6, "Output-stationary 64-element tile dataflow "
            "(nine tiles per full reduction)", ha="center", fontsize=11, weight="bold")

    # Time axis of streamed reduction elements.
    for t in range(6):
        box(ax, 0.5 + t * 1.15, 5.2, 1.0, 0.6, f"x[{t}]", "#eef3fb", fs=8)
    ax.text(7.4, 5.5, "...  TILE_L=64", fontsize=9, va="center")
    ax.text(0.5, 6.0, "broadcast activation stream (shared by all lanes):", fontsize=8.5)

    # Lanes holding stationary accumulators, each with its own weight.
    lane_y = [3.9, 2.9, 1.9]
    for i, yy in enumerate(lane_y):
        box(ax, 0.5, yy, 2.3, 0.7, f"lane {i}: w[{i}][t]", "#fdf2e0", fs=8)
        box(ax, 3.1, yy, 3.0, 0.7, f"acc[{i}] += x[t]*w[{i}][t]", "#ffffff", fs=8)
        box(ax, 6.4, yy, 2.6, 0.7, f"out chan {i} (stationary)", "#f2faf2", fs=8)
        arrow(ax, 2.8, yy + 0.35, 3.1, yy + 0.35)
        arrow(ax, 6.1, yy + 0.35, 6.4, yy + 0.35)
        # broadcast down from the activation stream
        ax.add_patch(FancyArrowPatch((1.0 + i * 0.3, 5.2), (1.6, yy + 0.7),
                                     arrowstyle="-|>", mutation_scale=10,
                                     color="#1f6fb2", lw=1.0, alpha=0.7))
    ax.text(6, 1.3, ". . . 128 lanes (128 output channels in parallel) . . .",
            ha="center", fontsize=9)

    ax.text(9.4, 3.0,
            "first -> clear tile acc\nlast  -> emit partial\n\n128 partials serialize.\nHost adds nine tile\npartials to reconstruct\nthe full L=576 result.",
            fontsize=8.5, va="center",
            bbox=dict(boxstyle="round", fc="#eaf6ff", ec="#88a"))

    ax.set_title("Figure 3. Tiled output-stationary dataflow: 64-element chiplet "
                 "partials, nine-way host accumulation", fontsize=11)
    fig.tight_layout()
    fig.savefig(FIGS / "fig3_dataflow.png", dpi=150)
    plt.close(fig)


def main():
    FIGS.mkdir(parents=True, exist_ok=True)
    block_diagram()
    dataflow_diagram()
    shutil.copyfile(BENCH / "roofline_final.png", FIGS / "fig1_roofline.png")
    shutil.copyfile(SIM / "final_waveform.png", FIGS / "fig4_waveform.png")
    print("wrote figures:", sorted(p.name for p in FIGS.glob("*.png")))


if __name__ == "__main__":
    main()
