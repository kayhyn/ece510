"""
Profile INT8 3x3 Convolution — YOLO-nano project algorithm
============================================================
This script implements the exact operation the accelerator will perform:
a 3×3 convolution with INT8 weights and activations, fused with ReLU,
on a representative YOLO-nano layer.

Representative layer chosen (YOLO-nano early backbone):
  Input:  52 × 52 × 64   (H × W × Cin)
  Kernel: 3 × 3 × 64 × 128  (Kh × Kw × Cin × Cout)
  Output: 52 × 52 × 128  (same-padding, stride 1)

We profile with cProfile across 15 runs.
"""

import cProfile
import pstats
import io
import numpy as np
import time

# ── Layer dimensions (representative YOLO-nano conv layer) ──────────
H, W, CIN, COUT = 52, 52, 64, 128
KH, KW = 3, 3
PAD = 1  # same-padding
STRIDE = 1
NUM_RUNS = 15

def generate_inputs():
    """Generate random INT8 feature map and weights."""
    ifmap = np.random.randint(-128, 127, size=(H, W, CIN), dtype=np.int8)
    weights = np.random.randint(-128, 127, size=(COUT, KH, KW, CIN), dtype=np.int8)
    bias = np.zeros(COUT, dtype=np.int32)
    return ifmap, weights, bias

def pad_input(ifmap):
    """Zero-pad the input feature map."""
    return np.pad(ifmap, ((PAD, PAD), (PAD, PAD), (0, 0)),
                  mode='constant', constant_values=0)

def conv3x3_int8(ifmap_padded, weights, bias):
    """
    Perform 3×3 INT8 convolution with fused ReLU.
    This is the DOMINANT KERNEL — the exact operation the accelerator targets.
    Accumulation in INT32, output clamped to INT8 after ReLU.
    """
    out_h = H
    out_w = W
    output = np.zeros((out_h, out_w, COUT), dtype=np.int32)

    for oh in range(out_h):
        for ow in range(out_w):
            # Extract the 3×3×Cin patch
            patch = ifmap_padded[oh:oh+KH, ow:ow+KW, :].astype(np.int32)
            for co in range(COUT):
                kern = weights[co].astype(np.int32)  # (KH, KW, CIN)
                output[oh, ow, co] = np.sum(patch * kern) + bias[co]

    # Fused ReLU + clamp to INT8 range
    output = np.clip(output, 0, 127).astype(np.int8)
    return output

def conv3x3_int8_vectorized(ifmap_padded, weights, bias):
    """
    Vectorized 3×3 INT8 convolution with fused ReLU.
    Uses im2col-style reshaping — closer to how a real CPU executes this
    via BLAS, and what the profiler would see on a PyTorch path.
    """
    out_h, out_w = H, W
    # im2col: extract all patches as a 2D matrix
    patches = np.zeros((out_h * out_w, KH * KW * CIN), dtype=np.int32)
    for oh in range(out_h):
        for ow in range(out_w):
            patches[oh * out_w + ow, :] = ifmap_padded[oh:oh+KH, ow:ow+KW, :].flatten().astype(np.int32)

    # Reshape weights to (COUT, KH*KW*CIN) and do matmul
    w_mat = weights.reshape(COUT, -1).astype(np.int32).T  # (KH*KW*CIN, COUT)
    output = patches @ w_mat + bias  # (out_h*out_w, COUT)

    # Fused ReLU + clamp
    output = np.clip(output, 0, 127).astype(np.int8)
    return output.reshape(out_h, out_w, COUT)

def run_single_inference():
    """One full forward pass: generate, pad, convolve."""
    ifmap, weights, bias = generate_inputs()
    ifmap_padded = pad_input(ifmap)
    output = conv3x3_int8_vectorized(ifmap_padded, weights, bias)
    return output

def run_all():
    """Run NUM_RUNS inferences (the profiled entry point)."""
    for _ in range(NUM_RUNS):
        run_single_inference()

# ── Profile ─────────────────────────────────────────────────────────
if __name__ == "__main__":
    # Warm-up
    run_single_inference()

    # Profile
    pr = cProfile.Profile()
    pr.enable()
    run_all()
    pr.disable()

    # Save results
    s = io.StringIO()
    ps = pstats.Stats(pr, stream=s).sort_stats('cumulative')
    ps.print_stats()
    profile_text = s.getvalue()

    with open("project_profile.txt", "w") as f:
        f.write(f"=" * 72 + "\n")
        f.write(f"YOLO-nano INT8 3x3 Convolution — cProfile Results\n")
        f.write(f"Layer: {H}x{W}x{CIN} -> 3x3 conv -> {H}x{W}x{COUT}\n")
        f.write(f"Runs: {NUM_RUNS}\n")
        f.write(f"=" * 72 + "\n\n")
        f.write(profile_text)

    print(profile_text[:3000])
    print("\n--- Saved to project_profile.txt ---")

    # Also measure wall-clock per-run
    times = []
    for _ in range(NUM_RUNS):
        t0 = time.perf_counter()
        run_single_inference()
        t1 = time.perf_counter()
        times.append(t1 - t0)
    avg_ms = np.mean(times) * 1000
    std_ms = np.std(times) * 1000
    print(f"\nWall-clock per inference: {avg_ms:.1f} ± {std_ms:.1f} ms")

    # Append timing summary
    with open("project_profile.txt", "a") as f:
        f.write(f"\n{'=' * 72}\n")
        f.write(f"WALL-CLOCK TIMING (per inference, {NUM_RUNS} runs)\n")
        f.write(f"Mean: {avg_ms:.1f} ms | Std: {std_ms:.1f} ms\n")
        f.write(f"Individual runs (ms): {[round(t*1000,1) for t in times]}\n")
