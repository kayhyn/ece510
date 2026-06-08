#!/usr/bin/env python3
"""Generate the annotated final production accel_top waveform from the VCD."""

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

    bits = ["rst", "s_tvalid", "s_tready", "comp_first", "comp_last",
            "array_in_valid", "array_in_first", "array_in_last",
            "array_out_valid", "draining", "m_tvalid", "m_tready"]

    # Panel A: first compute tile enters the array after its weight-load phase.
    start_cyc = find_first_edge(s["array_in_valid"]) or 4
    a0 = (start_cyc - 5) * CLK_PS
    a1 = (start_cyc + 12) * CLK_PS

    # Panel B: first 64-tap partial result enters the serializer.
    out_cyc = find_first_edge(s["array_out_valid"]) or 70
    b0 = (out_cyc - 4) * CLK_PS
    b1 = (out_cyc + 10) * CLK_PS

    fig, (axa, axb) = plt.subplots(2, 1, figsize=(12, 9))

    draw_panel(
        axa, s, a0, a1, bits,
        "M4 Production Waveform (A): first 64-tap compute tile enters accel_top",
        [(start_cyc, 1, "first compute beat reaches array;\narray_in_first starts partial sum", "#1a6"),
         (start_cyc + 1, 0, "one reduction element\naccepted per cycle", "#15c")],
    )

    drain_cyc = find_first_edge(s["m_tvalid"], after_cyc=out_cyc - 2) or (out_cyc + 1)
    draw_panel(
        axb, s, b0, b1, bits,
        "M4 Production Waveform (B): 64-tap partial result serializes over AXI4-Stream",
        [(out_cyc, 1, "array_out_valid:\n64-tap partial complete", "#d60"),
         (drain_cyc, 0, "draining/m_tvalid:\n128 channel beats begin", "#c06")],
    )

    fig.suptitle("M4 synthesized configuration: accel_top, L_MAX=64, "
                 "narrow AXI4-Stream + serializer", fontsize=11)
    fig.tight_layout(rect=[0, 0, 1, 0.97])
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(OUT_PATH, dpi=150)
    print(f"wrote {OUT_PATH}  (input start cyc={start_cyc}, "
          f"out cyc={out_cyc}, drain cyc={drain_cyc})")


if __name__ == "__main__":
    main()
