"""
CF09 Task 6 -- Re-run the M1 software baseline on the same hardware as M1.
=========================================================================
Same representative YOLO-nano layer and same vectorized im2col+GEMM kernel
used in the M1 baseline (project/m1/sw_baseline.md, cf02 profile_conv.py):

  Input:  52 x 52 x 64    (H x W x Cin)
  Kernel: 3 x 3 x 64 x 128 (Kh x Kw x Cin x Cout), stride 1, same-pad
  Output: 52 x 52 x 128
  Dtype:  INT8 operands, INT32 accumulation

Records: execution time (ms), throughput (FLOP/s, layers/s), peak memory (MB).
Writes a machine-readable summary to sw_baseline_result.json.
"""

import json
import time
import resource
import platform
import numpy as np

H, W, CIN, COUT = 52, 52, 64, 128
KH, KW = 3, 3
PAD = 1
NUM_RUNS = 15

MACS = (KH * KW * CIN) * (H * W * COUT)   # 199,360,512
FLOPS = 2 * MACS                          # 398,721,024


def make_inputs():
    ifmap = np.random.randint(-128, 127, size=(H, W, CIN), dtype=np.int8)
    weights = np.random.randint(-128, 127, size=(COUT, KH, KW, CIN), dtype=np.int8)
    bias = np.zeros(COUT, dtype=np.int32)
    return ifmap, weights, bias


def conv3x3_int8_vectorized(ifmap_padded, weights, bias):
    """im2col + GEMM, identical to the M1 baseline dominant kernel."""
    out_h, out_w = H, W
    patches = np.zeros((out_h * out_w, KH * KW * CIN), dtype=np.int32)
    for oh in range(out_h):
        for ow in range(out_w):
            patches[oh * out_w + ow, :] = \
                ifmap_padded[oh:oh + KH, ow:ow + KW, :].flatten().astype(np.int32)
    w_mat = weights.reshape(COUT, -1).astype(np.int32).T
    output = patches @ w_mat + bias
    output = np.clip(output, 0, 127).astype(np.int8)
    return output.reshape(out_h, out_w, COUT)


def one_inference():
    ifmap, weights, bias = make_inputs()
    ifmap_padded = np.pad(ifmap, ((PAD, PAD), (PAD, PAD), (0, 0)),
                          mode="constant", constant_values=0)
    return conv3x3_int8_vectorized(ifmap_padded, weights, bias)


def main():
    one_inference()  # warm-up

    times = []
    for _ in range(NUM_RUNS):
        t0 = time.perf_counter()
        one_inference()
        t1 = time.perf_counter()
        times.append(t1 - t0)

    times_ms = sorted(t * 1000 for t in times)
    median_ms = times_ms[len(times_ms) // 2]
    mean_ms = sum(times_ms) / len(times_ms)
    std_ms = (sum((t - mean_ms) ** 2 for t in times_ms) / len(times_ms)) ** 0.5

    # Peak resident memory of this process.
    maxrss = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    # macOS reports ru_maxrss in bytes; Linux in kilobytes.
    peak_mb = maxrss / (1024 * 1024) if platform.system() == "Darwin" else maxrss / 1024

    throughput_flops = FLOPS / (median_ms / 1000.0)
    layers_per_s = 1000.0 / median_ms

    result = {
        "label": "measured",
        "platform": f"{platform.system()} {platform.machine()} (Apple M1 Pro, same as M1)",
        "kernel": "3x3 INT8 conv, 52x52x64 -> 52x52x128 (im2col + GEMM)",
        "dtype": "INT8 operands, INT32 accumulate",
        "num_runs": NUM_RUNS,
        "total_FLOPs": FLOPS,
        "median_ms": round(median_ms, 3),
        "mean_ms": round(mean_ms, 3),
        "std_ms": round(std_ms, 3),
        "throughput_GFLOPs": round(throughput_flops / 1e9, 4),
        "layers_per_sec": round(layers_per_s, 3),
        "peak_rss_MB": round(peak_mb, 1),
        "all_times_ms": [round(t, 2) for t in times_ms],
    }

    with open("sw_baseline_result.json", "w") as f:
        json.dump(result, f, indent=2)

    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
