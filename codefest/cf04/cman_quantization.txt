a)

max(|W|) = 2.31 (from element W[2,3] = -2.31)

S = 2.31 / 127 = 0.01818898

b)

[  47   -66    19   115]
[  -4    50  -103     7]
[  85     2   -24  -127]
[ -10    57    42    30]


c)

[  0.854882  -1.200472   0.345591   2.091732]
[ -0.072756   0.909449  -1.873464   0.127323]
[  1.546063   0.036378  -0.436535  -2.310000]
[ -0.181890   1.036772   0.763937   0.545669]

d)

Per-element absolute errors |W - W_deq|:

[ 0.004882   0.000472   0.005591   0.008268 ]
[ 0.002756   0.000551   0.006536   0.007323 ]
[ 0.003937   0.006378   0.003465   0.000000 ]
[ 0.001890   0.006772   0.006063   0.004331 ]

Largest error: element [0,3], W = 2.10, W_deq = 2.091732, error = 0.008268.

MAE = 0.004326

Note: W[2,3] = -2.31 has zero error since it sets the scale and maps exactly to -127.

e)

With S_bad = 0.01, dividing W by S_bad gives values up to ±231, well outside [-128, 127]. After clamping:

[  85   -120    34   127 ]   <- 210 clipped to 127
[  -7    91  -128    12 ]   <- -188 clipped to -128
[ 127     3   -44  -128 ]   <- 155 clipped, -231 clipped
[ -18   103    77    55 ]

Dequantized:

[  0.85   -1.20    0.34    1.27 ]
[ -0.07    0.91   -1.28    0.12 ]
[  1.27    0.03   -0.44   -1.28 ]
[ -0.18    1.03    0.77    0.55 ]

MAE = 0.171250 (about 40x worse than the proper scale).

When S is too small, the quantized values overflow the INT8 range and get clipped, so all large-magnitude weights collapse to the INT8 limits and lose their actual values.
