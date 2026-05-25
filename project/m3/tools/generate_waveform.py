#!/usr/bin/env python3
"""Generate the annotated M3 waveform image from the simulator VCD."""

from pathlib import Path

import matplotlib.pyplot as plt


ROOT = Path(__file__).resolve().parents[3]
VCD_PATH = ROOT / "project" / "m3" / "sim" / "top.vcd"
OUT_PATH = ROOT / "project" / "m3" / "sim" / "cosim_waveform.png"

SIGNALS = {
    "s_axis_tvalid": "0",
    "s_axis_tready": "!",
    "m_axis_tvalid": '"',
    "m_axis_tready": "*",
    "compute_busy": "&",
    "compute_done": "%",
    "start": "D",
    "result_response_valid": "B",
}


def parse_vcd(path):
    times = {name: [0] for name in SIGNALS}
    values = {name: [0] for name in SIGNALS}
    current_time = 0

    for raw_line in path.read_text().splitlines():
        line = raw_line.strip()
        if not line:
            continue
        if line.startswith("#"):
            current_time = int(line[1:])
            continue
        if line[0] in "01xz":
            value = line[0]
            ident = line[1:]
            for name, signal_id in SIGNALS.items():
                if ident == signal_id:
                    times[name].append(current_time / 1000.0)
                    values[name].append(1 if value == "1" else 0)
                    break

    return times, values


def main():
    times, values = parse_vcd(VCD_PATH)
    labels = [
        "s_axis_tvalid",
        "s_axis_tready",
        "start",
        "compute_busy",
        "compute_done",
        "result_response_valid",
        "m_axis_tvalid",
        "m_axis_tready",
    ]

    fig, ax = plt.subplots(figsize=(13, 6.5))
    for row, name in enumerate(labels):
        y_base = len(labels) - row
        ax.step(times[name], [y_base + 0.7 * v for v in values[name]],
                where="post", linewidth=1.8, label=name)
        ax.text(-8, y_base + 0.25, name, ha="right", va="center", fontsize=9)

    ax.axvspan(20, 420, color="#e8f1ff", alpha=0.7)
    ax.axvspan(430, 540, color="#e8ffe8", alpha=0.7)
    ax.axvspan(550, 610, color="#fff2d9", alpha=0.8)
    ax.text(220, len(labels) + 0.95, "Host writes activation/weight/bias/start commands",
            ha="center", fontsize=9)
    ax.text(485, len(labels) + 1.35, "Compute core accumulates 9 INT8 products",
            ha="center", fontsize=9)
    ax.text(580, len(labels) + 0.95, "Host reads result response",
            ha="center", fontsize=9)

    ax.set_title("M3 End-to-End Co-Simulation Waveform")
    ax.set_xlabel("Simulation time (ns)")
    ax.set_yticks([])
    ax.set_ylim(0.7, len(labels) + 1.8)
    ax.set_xlim(left=0)
    ax.grid(axis="x", linestyle=":", alpha=0.4)
    fig.tight_layout()
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(OUT_PATH, dpi=160)


if __name__ == "__main__":
    main()
