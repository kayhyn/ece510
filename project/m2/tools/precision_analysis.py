#!/usr/bin/env python3
"""Reproduce the M2 INT8 precision analysis."""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parents[3]
OUT_PATH = ROOT / "project" / "m2" / "sim" / "precision_analysis.json"

SAMPLES = 1000
TAPS = 9
SEED = 510
ACTIVATION_SCALE = 1.0 / 127.0
WEIGHT_SCALE = 1.0 / 127.0
BIAS_SCALE = ACTIVATION_SCALE * WEIGHT_SCALE


def quantize_int8(values: np.ndarray, scale: float) -> np.ndarray:
    quantized = np.rint(values / scale)
    return np.clip(quantized, -128, 127).astype(np.int8)


def main() -> None:
    rng = np.random.default_rng(SEED)

    activations_fp32 = rng.uniform(-1.0, 1.0, size=(SAMPLES, TAPS)).astype(np.float32)
    weights_fp32 = rng.uniform(-1.0, 1.0, size=(SAMPLES, TAPS)).astype(np.float32)
    bias_fp32 = rng.uniform(-0.25, 0.25, size=(SAMPLES,)).astype(np.float32)

    activations_int8 = quantize_int8(activations_fp32, ACTIVATION_SCALE)
    weights_int8 = quantize_int8(weights_fp32, WEIGHT_SCALE)
    bias_int32 = np.rint(bias_fp32 / BIAS_SCALE).astype(np.int32)

    fp32_reference = np.sum(activations_fp32 * weights_fp32, axis=1, dtype=np.float32) + bias_fp32
    int32_accumulator = (
        np.sum(
            activations_int8.astype(np.int32) * weights_int8.astype(np.int32),
            axis=1,
            dtype=np.int32,
        )
        + bias_int32
    )
    int8_dequantized = int32_accumulator.astype(np.float32) * np.float32(BIAS_SCALE)
    abs_error = np.abs(int8_dequantized - fp32_reference)

    metrics = {
        "samples": SAMPLES,
        "taps_per_sample": TAPS,
        "seed": SEED,
        "activation_scale": ACTIVATION_SCALE,
        "weight_scale": WEIGHT_SCALE,
        "bias_scale": BIAS_SCALE,
        "mean_absolute_error": float(np.mean(abs_error)),
        "max_absolute_error": float(np.max(abs_error)),
        "rms_error": float(np.sqrt(np.mean(abs_error * abs_error))),
        "p95_absolute_error": float(np.percentile(abs_error, 95)),
        "mean_abs_fp32_reference": float(np.mean(np.abs(fp32_reference))),
        "relative_mae_vs_mean_abs_reference": float(np.mean(abs_error) / np.mean(np.abs(fp32_reference))),
        "first_five": [
            {
                "fp32_reference": float(fp32_reference[i]),
                "int32_accumulator": int(int32_accumulator[i]),
                "int8_dequantized": float(int8_dequantized[i]),
                "absolute_error": float(abs_error[i]),
            }
            for i in range(5)
        ],
    }

    OUT_PATH.write_text(json.dumps(metrics, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(metrics, indent=2))


if __name__ == "__main__":
    main()
