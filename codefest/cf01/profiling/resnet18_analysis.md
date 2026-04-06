# ResNet-18 Profile Analysis

**Model:** ResNet-18 (torchvision, random weights)
**Input:** batch=1, FP32, 3×224×224
**Tool:** torchinfo v1.8.0 / PyTorch 2.7.0
**Full profile:** `resnet18_profile.txt`

---

## Top 5 Layers by MAC Count

> **Note:** 13 convolution layers are tied at 115,605,504 MACs (the 3×3 convs in stages 1–4).
> The stem `conv1` is uniquely highest. The four runners-up below are the first four tied layers in network order.

| Rank | Layer Name | Input Shape | Output Shape | MACs | Parameters |
|------|-----------|-------------|--------------|------|------------|
| 1 | `conv1` (stem) | [1, 3, 224, 224] | [1, 64, 112, 112] | 118,013,952 | 9,408 |
| 2 | `layer1.0.conv1` | [1, 64, 56, 56] | [1, 64, 56, 56] | 115,605,504 | 36,864 |
| 3 | `layer1.0.conv2` | [1, 64, 56, 56] | [1, 64, 56, 56] | 115,605,504 | 36,864 |
| 4 | `layer1.1.conv1` | [1, 64, 56, 56] | [1, 64, 56, 56] | 115,605,504 | 36,864 |
| 5 | `layer1.1.conv2` | [1, 64, 56, 56] | [1, 64, 56, 56] | 115,605,504 | 36,864 |

**Total network MACs:** 1,814,083,944 (~1.81 G)
**Total parameters:** 11,689,512 (~11.7 M)

---

## Arithmetic Intensity: `conv1` (Stem Convolution)

`conv1` is the most MAC-intensive layer with **118,013,952 MACs**.

### Layer Configuration

| Property | Value |
|----------|-------|
| Kernel | 7×7, stride 2, padding 3 |
| Input channels | 3 |
| Output channels | 64 |
| Output spatial | 112×112 |
| Weight tensor | [64, 3, 7, 7] |

### Operation Count

```
MACs  = C_out × C_in × K_h × K_w × H_out × W_out
      = 64 × 3 × 7 × 7 × 112 × 112
      = 9,408 × 12,544
      = 118,013,952 MACs

FLOPs = 2 × MACs = 236,027,904  (1 multiply + 1 add per MAC)
```

### Bytes Accessed (FP32, All Tensors Loaded from DRAM, No Reuse)

| Tensor | Elements | Bytes (FP32 = 4 B) |
|--------|----------|--------------------|
| Weights | 64 × 3 × 7 × 7 = 9,408 | **37,632 B** |
| Input activations | 1 × 3 × 224 × 224 = 150,528 | **602,112 B** |
| Output activations | 1 × 64 × 112 × 112 = 802,816 | **3,211,264 B** |
| **Total** | | **3,851,008 B ≈ 3.67 MiB** |

### Arithmetic Intensity

```
AI (MACs/byte)  = 118,013,952 MACs  /  3,851,008 B  ≈  30.6 MACs/byte

AI (FLOPs/byte) = 236,027,904 FLOPs /  3,851,008 B  ≈  61.3 FLOPs/byte
```

### Interpretation

An arithmetic intensity of **~61 FLOPs/byte** sits well below the compute-to-bandwidth ridge point of typical modern hardware (e.g., ~250 FLOPs/byte on an A100 80 GB).
Under the **Roofline model**, `conv1` is **memory-bandwidth bound** when activations and weights are streamed from DRAM with no on-chip reuse.

The dominant byte cost is writing the output feature map (3.21 MB), which alone accounts for 83% of total data movement. In practice, tiling/blocking strategies that keep the 37 KB weight tensor in cache can raise effective AI significantly, but the large output map still forces substantial DRAM traffic.
