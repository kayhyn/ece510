import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches

# GTX 1080 Ti hardware specs
peak_flops_gflops = 11340.0   # GFLOP/s (FP32, boost clock ~1582 MHz, 3584 cores)
peak_bw_gbs       = 484.4     # GB/s (GDDR5X, 352-bit bus)
ridge_point        = peak_flops_gflops / peak_bw_gbs  # ~23.4 FLOP/Byte

# Measured kernel results (5-run average on N=1024 GEMM)
naive_gflops = 442.74
tiled_gflops = 1120.27

# Arithmetic intensity (FLOP/Byte)
# Naive: no data reuse; each thread reads A[row][0..N-1] sequentially and
# B[0..N-1][col] with stride-N, warp-level coalescing on A but stride waste on B.
# Effective AI ~ 0.5 FLOP/Byte (2N FLOPs / ~8N bytes per thread after coalescing).
# Tiled T=8: each output tile (8x8) reuses 8x8 tiles of A and B from shared mem.
# AI = T/4 = 8/4 = 2.0 FLOP/Byte.
ai_naive = 0.5
ai_tiled = 2.0

# ── Roofline curve ──────────────────────────────────────────────────────────
ai_range = np.logspace(-2, 3, 500)
roofline = np.minimum(peak_bw_gbs * ai_range, peak_flops_gflops)

fig, ax = plt.subplots(figsize=(9, 6))

ax.loglog(ai_range, roofline, 'k-', linewidth=2.5, label='Roofline (GTX 1080 Ti)')

# Ceilings at each kernel's AI
ceil_naive = min(peak_flops_gflops, ai_naive * peak_bw_gbs)
ceil_tiled = min(peak_flops_gflops, ai_tiled * peak_bw_gbs)

# Vertical dashed lines from x-axis up to roofline ceiling
ax.vlines(ai_naive, 1, ceil_naive, colors='steelblue', linestyles='--', linewidth=1.2, alpha=0.7)
ax.vlines(ai_tiled, 1, ceil_tiled, colors='darkorange', linestyles='--', linewidth=1.2, alpha=0.7)

# Ridge point
ax.axvline(ridge_point, color='gray', linestyle=':', linewidth=1.5, alpha=0.8)
ax.text(ridge_point * 1.08, 6000, f'Ridge\n{ridge_point:.1f} FLOP/B',
        fontsize=8, color='gray', va='center')

# Kernel data points
ax.scatter([ai_naive], [naive_gflops], color='steelblue', s=120, zorder=5)
ax.scatter([ai_tiled], [tiled_gflops], color='darkorange', s=120, zorder=5)

# Annotations
ax.annotate(
    f'gemm_naive\n{naive_gflops:.0f} GFLOP/s\n({naive_gflops/peak_flops_gflops*100:.1f}% of peak)\nAI={ai_naive} FLOP/B',
    xy=(ai_naive, naive_gflops), xytext=(0.08, 600),
    fontsize=8.5, color='steelblue',
    arrowprops=dict(arrowstyle='->', color='steelblue', lw=1.2),
)
ax.annotate(
    f'gemm_tiled (T=8)\n{tiled_gflops:.0f} GFLOP/s\n({tiled_gflops/peak_flops_gflops*100:.1f}% of peak)\nAI={ai_tiled} FLOP/B',
    xy=(ai_tiled, tiled_gflops), xytext=(6, 2200),
    fontsize=8.5, color='darkorange',
    arrowprops=dict(arrowstyle='->', color='darkorange', lw=1.2),
)

# Reference ceiling labels on right edge
ax.text(ai_range[-1] * 1.01, peak_flops_gflops, f'{peak_flops_gflops:.0f} GFLOP/s',
        fontsize=8, va='center', ha='left', color='black')
ax.text(ai_range[-1] * 1.01, peak_bw_gbs * ai_range[-1],
        f'{peak_bw_gbs:.0f} GB/s BW', fontsize=8, va='center', ha='left', color='black')

# "Memory-bound" / "Compute-bound" region labels
ax.text(0.05, 8000, 'Memory-bound', fontsize=9, color='dimgray', style='italic')
ax.text(30,   8000, 'Compute-bound', fontsize=9, color='dimgray', style='italic')

ax.set_xlabel('Arithmetic Intensity (FLOP/Byte)', fontsize=11)
ax.set_ylabel('Performance (GFLOP/s)', fontsize=11)
ax.set_title('Roofline Model — GEMM Kernels on NVIDIA GTX 1080 Ti\n(N=1024, FP32)', fontsize=12)
ax.set_xlim(0.02, 500)
ax.set_ylim(5, 30000)
ax.grid(True, which='both', linestyle='--', linewidth=0.5, alpha=0.5)

patch_naive = mpatches.Patch(color='steelblue', label='gemm_naive (443 GFLOP/s)')
patch_tiled = mpatches.Patch(color='darkorange', label='gemm_tiled T=8 (1120 GFLOP/s)')
ax.legend(handles=[patch_naive, patch_tiled], loc='upper left', fontsize=9)

plt.tight_layout()
plt.savefig('/home/kaylee/ece510/codefest/cf03/profiling/gemm_roofline.png', dpi=150)
print("Saved gemm_roofline.png")
