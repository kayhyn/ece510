## (a) Per-Layer MACs
 
| Layer | Formula | MACs |
|-------|---------|------|
| 1 (784 → 256) | 784 × 256 | 200,704 |
| 2 (256 → 128) | 256 × 128 | 32,768 |
| 3 (128 → 10) | 128 × 10 | 1,280 |

## (b) Total MACs

200,704 + 32,768 + 1,280 = **234,752**

## (c) Total trainable parameters

As each weight = one MAC, this is equal to the number of MACs as above.

## (d) Weight Memory

Each weight is stored as an FP32 which is 4 bytes. So 234,752 * 4 = **939,008 bytes**

## (e) Activation memory

Activations are inputs and all layer outputs. This means there are 784 + 256 + 128 + 10 = 1,178 total activations. These are also FP32s, which means they consume 1,178 * 4 = **4,712 bytes**.

## (f) Arithmetic Intensity

Each MAC requires one multiply and one add - two arithmetic operations. 2 * 234,752 = 469,504 total operations. 

The total memory usage is 939,008 + 4,712 = 943,720 bytes.

469,504 / 943,720 = **0.4975 FLOP/byte**
