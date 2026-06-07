#!/usr/bin/env python3
"""Generate the annotated M4 end-to-end waveform image from the simulator VCD.

Produces project/m4/sim/final_waveform.png: two zoom panels of one end-to-end
transaction through the integrated `top` (AXI4-Stream stream_if -> compute_core
-> mac_array): (A) the input stream start, showing the AXI4-Stream handshake and
the first/last tags entering the array; (B) the first 128-channel output pixel
draining on the output stream after the L=576 reduction.
"""

from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

ROOT = Path(__file__).resolve().parents[3]
VCD_PATH = ROOT / "project" / "m4" / "sim" / "final_top.vcd"
OUT_PATH = ROOT / "project" / "m4" / "sim" / "final_waveform.png"

CLK_PS = 10000  # 10 ns clock period in ps (tb toggles every 5 ns)


def parse_vcd(path):
    """Return {signal_name: [(time_ps, int_value), ...]} for 1-bit and bus vars."""
    id_to_name = {}
    width = {}
    in_defs = True
    series = {}
    t = 0
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line:
            continue
        if in_defs:
            if line.startswith("$var"):
                parts = line.split()
                w = int(parts[2])
                ident = parts[3]
                name = parts[4]
                id_to_name[ident] = name
                width[ident] = w
                series[name] = []
            elif line.startswith("$enddefinitions"):
                in_defs = False
            continue
        if line.startswith("#"):
            t = int(line[1:])
            continue
        if line[0] in "01xz":
            val = line[0]
            ident = line[1:]
            if ident in id_to_name:
                series[id_to_name[ident]].append((t, 0 if val in "xz" else int(val)))
        elif line[0] in "bB":
            tok = line[1:].split()
            bits, ident = tok[0], tok[1]
            if ident in id_to_name:
                try:
                    v = int(bits.replace("x", "0").replace("z", "0"), 2)
                    w = width[ident]
                    if v >= (1 << (w - 1)):  # interpret as signed two's complement
                        v -= (1 << w)
                except ValueError:
                    v = 0
                series[id_to_name[ident]].append((t, v))
    return series


def value_at(events, t):
    v = 0
    for et, ev in events:
        if et <= t:
            v = ev
        else:
            break
    return v


def draw_panel(ax, series, t0_ps, t1_ps, bit_signals, title, annotations):
    cyc0 = t0_ps // CLK_PS
    cyc1 = t1_ps // CLK_PS
    cycles = list(range(cyc0, cyc1 + 1))
    n = len(bit_signals)
    for row, name in enumerate(bit_signals):
        y_base = n - row
        xs, ys = [], []
        for cyc in cycles:
            t = cyc * CLK_PS + CLK_PS // 4  # sample shortly after the posedge
            v = value_at(series[name], t)
            xs.append(cyc)
            ys.append(y_base + 0.66 * (1 if v else 0))
        ax.step(xs, ys, where="post", linewidth=1.7)
        ax.text(cyc0 - 0.6, y_base + 0.25, name, ha="right", va="center", fontsize=8.5)
    for cyc, level, text, color in annotations:
        ytop = n + 0.45 + 0.95 * level
        ax.annotate(text, xy=(cyc, n + 0.4), xytext=(cyc, ytop),
                    fontsize=8.5, ha="center", va="bottom", color=color,
                    arrowprops=dict(arrowstyle="->", color=color, lw=1.0))
        ax.axvline(cyc, color=color, linestyle=":", alpha=0.5, linewidth=1.0)
    ax.set_title(title, fontsize=10, pad=26)
    ax.set_xlabel("Cycle (10 ns clock)")
    ax.set_yticks([])
    ax.set_xlim(cyc0 - 4, cyc1 + 0.5)
    ax.set_ylim(0.6, n + 2.6)
    ax.grid(axis="x", linestyle=":", alpha=0.35)


def find_first_edge(events, after_cyc=0):
    for t, v in events:
        if v == 1 and t // CLK_PS >= after_cyc:
            return t // CLK_PS
    return None


def main():
    s = parse_vcd(VCD_PATH)

    bits = ["rst", "s_tvalid", "s_tready", "s_first", "s_last",
            "core_in_valid", "core_in_first", "core_in_last",
            "core_out_valid", "m_tvalid", "m_tready"]

    # Panel A: input stream start (first ~16 cycles after reset deassert).
    start_cyc = find_first_edge(s["s_tvalid"]) or 4
    a0 = (start_cyc - 2) * CLK_PS
    a1 = (start_cyc + 12) * CLK_PS

    # Panel B: first output pixel draining on the output stream.
    out_cyc = find_first_edge(s["core_out_valid"]) or 580
    b0 = (out_cyc - 4) * CLK_PS
    b1 = (out_cyc + 10) * CLK_PS

    fig, (axa, axb) = plt.subplots(2, 1, figsize=(12, 9))

    draw_panel(
        axa, s, a0, a1, bits,
        "M4 End-to-End Waveform (A): input AXI4-Stream start -> array",
        [(start_cyc, 1, "s_tvalid & s_tready handshake;\ns_first tags pixel 0", "#1a6"),
         (start_cyc + 1, 0, "beat registered ->\ncore_in_valid/core_in_first", "#15c")],
    )

    drain_cyc = find_first_edge(s["m_tvalid"], after_cyc=out_cyc - 2) or (out_cyc + 1)
    draw_panel(
        axb, s, b0, b1, bits,
        "M4 End-to-End Waveform (B): first output pixel drains "
        "(128 channels after L=576 reduction)",
        [(out_cyc, 1, "core_out_valid pulse\n(pixel 0 complete)", "#d60"),
         (drain_cyc, 0, "m_tvalid & m_tready:\n128-ch result accepted", "#c06")],
    )

    fig.suptitle("M4 128-MAC accelerator: one end-to-end transaction "
                 "(top = stream_if + compute_core/mac_array)", fontsize=11)
    fig.tight_layout(rect=[0, 0, 1, 0.97])
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(OUT_PATH, dpi=150)
    print(f"wrote {OUT_PATH}  (input start cyc={start_cyc}, "
          f"out cyc={out_cyc}, drain cyc={drain_cyc})")


if __name__ == "__main__":
    main()
