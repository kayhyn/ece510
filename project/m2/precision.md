# Precision and Data Format

## Numerical Format

The M2 compute core uses signed INT8 activations and signed INT8 weights with
signed INT32 accumulation. This matches the M1 software baseline in
`project/m1/sw_baseline.md`, where the representative YOLO-nano layer is
modeled with INT8 activations/weights and INT32 accumulation. The RTL does not
use a custom fixed-point fractional format internally: each input sample is a
two's-complement integer in the range [-128, 127], each product is a signed
16-bit value, and the sum is accumulated into a signed 32-bit register.

For the optional quantization analysis below, real-valued inputs in [-1, 1] are
mapped to INT8 with symmetric scale factors:

```text
activation_scale = 1 / 127 = 0.007874015748031496
weight_scale     = 1 / 127 = 0.007874015748031496
bias_scale       = activation_scale * weight_scale
                 = 0.00006200012400024799
```

Rounding is round-to-nearest using NumPy's `rint`, followed by saturation to
the signed INT8 range. Bias is quantized to INT32 using `bias_scale`.

## Rationale

INT8 is the right precision for this milestone because the project target is a
YOLO-nano edge-inference convolution accelerator, and the profiled dominant
kernel is a 3x3 convolution with high arithmetic intensity. M1 reports an
arithmetic intensity of about 673 FLOP/byte for the representative
52x52x64-to-128 layer. Reducing operands from FP32 to INT8 cuts activation and
weight traffic by 4x and allows a much smaller multiplier than FP32, which is
important for the planned MAC-array architecture. The next-wider common format,
FP16, would simplify comparison to floating-point references but would spend
more area and bandwidth than needed for an edge object-detection workload. The
next-narrower common format, INT4, would reduce bandwidth further but would be
riskier without a trained quantization-aware model or calibration set in this
repository.

## Error Analysis

The analysis is reproducible with:

```sh
python3 project/m2/tools/precision_analysis.py
```

The script writes the measured values to
`project/m2/sim/precision_analysis.json`. It evaluates 1000 deterministic
9-tap dot-product samples using seed 510. These are numerical analysis vectors,
not a labeled object-detection validation dataset, so no classification
accuracy delta is reported. The FP32 reference is computed from the unquantized
real-valued inputs. The INT8 path quantizes activations and weights, accumulates
the INT8 products in INT32, then dequantizes the accumulator by `bias_scale`.

Results from the committed run:

```text
samples                         = 1000
mean_absolute_error             = 0.004511093255132437
max_absolute_error              = 0.017759695649147034
rms_error                       = 0.005570434033870697
p95_absolute_error              = 0.010876733064651487
mean_abs_fp32_reference         = 0.8312984108924866
relative_mae_vs_mean_abs_ref    = 0.005426562856882811
```

The first five sample records, including FP32 reference, INT32 accumulator,
dequantized INT8 result, and absolute error, are stored in the JSON output so
the aggregate numbers can be spot-checked without rerunning the script.

## Acceptability

The observed mean absolute error is about 0.54% of the mean absolute FP32
reference magnitude, and the maximum absolute error across 1000 samples is
0.0178 on an input range scaled to roughly [-1, 1]. For this M2 RTL milestone,
that is acceptable because the compute core is intended to validate the
integer datapath, handshake timing, and accumulation behavior rather than final
model accuracy. A final accelerator should still be checked against a real
YOLO-nano calibration or validation set before claiming task-level accuracy.
