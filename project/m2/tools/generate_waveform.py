#!/usr/bin/env python3
"""Generate waveform.png from simulator-produced VCD traces."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt


ROOT = Path(__file__).resolve().parents[3]
SIM_DIR = ROOT / "project" / "m2" / "sim"


@dataclass
class VcdSignal:
    code: str
    width: int
    name: str
    values: list[tuple[int, str]]


def parse_vcd(path: Path) -> dict[str, VcdSignal]:
    signals_by_code: dict[str, VcdSignal] = {}
    names_by_code: dict[str, list[str]] = {}
    scope: list[str] = []
    time_ps = 0
    in_definitions = True

    with path.open(encoding="utf-8") as f:
        for raw_line in f:
            line = raw_line.strip()
            if not line:
                continue

            if in_definitions:
                fields = line.split()
                if line.startswith("$scope"):
                    scope.append(fields[2])
                elif line.startswith("$upscope"):
                    scope.pop()
                elif line.startswith("$var"):
                    width = int(fields[2])
                    code = fields[3]
                    signal_name = fields[4]
                    full_name = ".".join(scope + [signal_name])
                    names_by_code.setdefault(code, []).append(full_name)
                    signals_by_code.setdefault(code, VcdSignal(code, width, full_name, []))
                elif line.startswith("$enddefinitions"):
                    in_definitions = False
                continue

            if line.startswith("#"):
                time_ps = int(line[1:])
            elif line[0] in "01xz":
                code = line[1:]
                if code in signals_by_code:
                    signals_by_code[code].values.append((time_ps, line[0]))
            elif line[0] == "b":
                value, code = line[1:].split(maxsplit=1)
                if code in signals_by_code:
                    signals_by_code[code].values.append((time_ps, value))

    by_name: dict[str, VcdSignal] = {}
    for code, signal in signals_by_code.items():
        for name in names_by_code[code]:
            by_name[name] = VcdSignal(code, signal.width, name, signal.values)
    return by_name


def find_signal(signals: dict[str, VcdSignal], full_name: str) -> VcdSignal:
    try:
        return signals[full_name]
    except KeyError as exc:
        choices = "\n".join(sorted(signals))
        raise KeyError(f"Missing signal {full_name}. Available:\n{choices}") from exc


def scalar_steps(signal: VcdSignal) -> tuple[list[float], list[int]]:
    xs: list[float] = []
    ys: list[int] = []
    for time_ps, value in signal.values:
        if value in "01":
            xs.append(time_ps / 1000.0)
            ys.append(int(value))
    return xs, ys


def last_binary_value(signal: VcdSignal) -> int | None:
    for _, value in reversed(signal.values):
        if all(bit in "01" for bit in value):
            return int(value, 2)
    return None


def plot_scalar_group(ax: plt.Axes, signals: list[tuple[VcdSignal, str]]) -> None:
    for offset, (signal, label) in enumerate(reversed(signals)):
        xs, ys = scalar_steps(signal)
        ax.step(xs, [y + offset for y in ys], where="post", label=label)
    ax.set_yticks(list(range(len(signals))))
    ax.set_yticklabels([label for _, label in reversed(signals)])
    ax.grid(True, axis="x", alpha=0.3)


def main() -> None:
    compute = parse_vcd(SIM_DIR / "compute_core.vcd")
    axis = parse_vcd(SIM_DIR / "interface.vcd")

    fig, axes = plt.subplots(2, 1, figsize=(12, 7))

    compute_signals = [
        (find_signal(compute, "tb_compute_core.rst"), "rst"),
        (find_signal(compute, "tb_compute_core.start"), "start"),
        (find_signal(compute, "tb_compute_core.busy"), "busy"),
        (find_signal(compute, "tb_compute_core.done"), "done"),
    ]
    plot_scalar_group(axes[0], compute_signals)
    result = last_binary_value(find_signal(compute, "tb_compute_core.result"))
    expected = last_binary_value(find_signal(compute, "tb_compute_core.expected"))
    accumulator = last_binary_value(find_signal(compute, "tb_compute_core.dut.accumulator"))
    axes[0].set_title("compute_core VCD trace")
    axes[0].set_xlabel("Time (ns)")
    axes[0].annotate(
        f"Captured from compute_core.vcd\nexpected={expected_signed(expected)} result={expected_signed(result)} accumulator={expected_signed(accumulator)}",
        xy=(90, 0.5),
        xytext=(45, 3.4),
        arrowprops={"arrowstyle": "->"},
    )

    axis_signals = [
        (find_signal(axis, "tb_interface.s_axis_tvalid"), "s_axis_tvalid"),
        (find_signal(axis, "tb_interface.s_axis_tready"), "s_axis_tready"),
        (find_signal(axis, "tb_interface.m_axis_tvalid"), "m_axis_tvalid"),
        (find_signal(axis, "tb_interface.m_axis_tready"), "m_axis_tready"),
    ]
    plot_scalar_group(axes[1], axis_signals)
    config = last_binary_value(find_signal(axis, "tb_interface.config_reg"))
    response = last_binary_value(find_signal(axis, "tb_interface.m_axis_tdata"))
    axes[1].set_title("axis_interface VCD trace")
    axes[1].set_xlabel("Time (ns)")
    axes[1].annotate(
        f"Captured from interface.vcd\nconfig=0x{config:07x} response=0x{response:08x}",
        xy=(65, 1.0),
        xytext=(25, 3.4),
        arrowprops={"arrowstyle": "->"},
    )

    fig.tight_layout()
    fig.savefig(SIM_DIR / "waveform.png", dpi=160)


def expected_signed(value: int | None, width: int = 32) -> int | None:
    if value is None:
        return None
    sign_bit = 1 << (width - 1)
    return value - (1 << width) if value & sign_bit else value


if __name__ == "__main__":
    main()
