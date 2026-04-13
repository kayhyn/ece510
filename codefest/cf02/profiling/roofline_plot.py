"""
Roofline Model — YOLO-nano INT8 3×3 Convolution
=================================================
Target hardware: Laptop CPU (representative modern Intel i7, ~12th gen)
Accelerator:     Custom INT8 MAC array (project design)
"""

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np

# ── Hardware specs ──────────────────────────────────────────────────
# Laptop CPU: Apple M1 Pro (8 performance + 2 efficiency cores)
#   Peak FP32:  ~200 GFLOPS (8 P-cores × NEON, Apple's published ~11 TFLOPS
#               is GPU; CPU NEON FP32 peak ≈ 200 GFLOPS)
#   Peak mem BW: LPDDR5 unified memory ≈ 200 GB/s
#   NumPy on M1 uses Accelerate/NEON, so FP32 peak is the relevant ceiling.

cpu_peak_gflops = 200.0       # GFLOP/s (FP32, NEON, 8 P-cores)
cpu_peak_bw     = 200.0       # GB/s (LPDDR5 unified memory)
cpu_ridge       = cpu_peak_gflops / cpu_peak_bw  # ≈ 2.34 FLOP/byte

# Custom INT8 Accelerator (project design target)
#   128 INT8 MAC units @ 250 MHz
#   Each MAC = 2 ops/cycle (1 mul + 1 add)
#   Peak: 128 × 2 × 250 MHz = 64 GOPS
#   On-chip SRAM BW: Two 256-bit ports @ 250 MHz = 2 × 8 B × 250 MHz = 4 GB/s
#   (This is the AXI-Stream interface BW to/from the array, not total SRAM BW)
#   Effective on-chip BW including weight SRAM: ~32 GB/s

accel_peak_gops = 64.0        # GOPS (INT8)
accel_peak_bw   = 32.0        # GB/s (on-chip SRAM)
accel_ridge     = accel_peak_gops / accel_peak_bw  # = 2.0 FLOP/byte

# ── Kernel data point ──────────────────────────────────────────────
kernel_ai     = 672.5         # FLOP/byte (from ai_calculation.md)
kernel_label  = "3×3 Conv\n(52×52×64→128)"

# The kernel's attainable perf on each platform
# (both are compute-bound since AI >> ridge point)
kernel_on_cpu   = cpu_peak_gflops     # compute-bound → hits ceiling
kernel_on_accel = accel_peak_gops     # compute-bound → hits ceiling

# ── Plot ────────────────────────────────────────────────────────────
fig, ax = plt.subplots(figsize=(10, 6))

ai_range = np.logspace(-1, 4, 500)  # FLOP/byte

# CPU roofline
cpu_roof = np.minimum(cpu_peak_gflops, cpu_peak_bw * ai_range)
ax.plot(ai_range, cpu_roof, 'b-', linewidth=2, label=f'M1 Pro CPU ({cpu_peak_gflops:.0f} GFLOP/s, {cpu_peak_bw:.0f} GB/s)')

# Accelerator roofline
accel_roof = np.minimum(accel_peak_gops, accel_peak_bw * ai_range)
ax.plot(ai_range, accel_roof, 'r--', linewidth=2, label=f'INT8 Accelerator ({accel_peak_gops:.0f} GOPS, {accel_peak_bw:.0f} GB/s)')

# Kernel on CPU
ax.plot(kernel_ai, kernel_on_cpu, 'bo', markersize=12, zorder=5)
ax.annotate(f'{kernel_label}\non M1 Pro CPU\nAI = {kernel_ai:.0f} FLOP/B',
            xy=(kernel_ai, kernel_on_cpu),
            xytext=(kernel_ai * 0.02, kernel_on_cpu * 1.1),
            fontsize=9, fontweight='bold', color='blue',
            arrowprops=dict(arrowstyle='->', color='blue', lw=1.5),
            bbox=dict(boxstyle='round,pad=0.3', facecolor='lightyellow', edgecolor='blue'))

# Kernel on Accelerator
ax.plot(kernel_ai, kernel_on_accel, 'r^', markersize=12, zorder=5)
ax.annotate(f'{kernel_label}\non Accelerator\nAI = {kernel_ai:.0f} FLOP/B',
            xy=(kernel_ai, kernel_on_accel),
            xytext=(kernel_ai * 0.08, kernel_on_accel * 0.08),
            fontsize=9, fontweight='bold', color='red',
            arrowprops=dict(arrowstyle='->', color='red', lw=1.5),
            bbox=dict(boxstyle='round,pad=0.3', facecolor='lightyellow', edgecolor='red'))

# Ridge points
ax.axvline(cpu_ridge, color='blue', linestyle=':', alpha=0.4, linewidth=1)
ax.text(cpu_ridge * 1.1, 0.15, f'CPU ridge\n{cpu_ridge:.1f} F/B', fontsize=8, color='blue', alpha=0.7)

ax.axvline(accel_ridge, color='red', linestyle=':', alpha=0.4, linewidth=1)
ax.text(accel_ridge * 0.25, 0.15, f'Accel ridge\n{accel_ridge:.1f} F/B', fontsize=8, color='red', alpha=0.7)

ax.set_xscale('log')
ax.set_yscale('log')
ax.set_xlabel('Arithmetic Intensity (FLOP/byte)', fontsize=12)
ax.set_ylabel('Attainable Performance (GFLOP/s or GOPS)', fontsize=12)
ax.set_title('Roofline Model — YOLO-nano INT8 3×3 Convolution Layer', fontsize=13, fontweight='bold')
ax.legend(loc='upper left', fontsize=9)
ax.set_xlim(0.1, 10000)
ax.set_ylim(0.1, 500)
ax.grid(True, which='both', alpha=0.3)

plt.tight_layout()
plt.savefig('roofline_project.png', dpi=150, bbox_inches='tight')
print("Saved roofline_project.png")
