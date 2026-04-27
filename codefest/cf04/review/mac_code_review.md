# CLLM MAC Code Review

## Model Mapping

- `hdl/mac_llm_A.v`: Claude Opus 4.7
- `hdl/mac_llm_B.v`: Claude Haiku 4.5

Both generated files were compiled with:

```sh
iverilog -g2012 -Wall -o <output>.vvp <mac_file>.v mac_tb.v
```

## Compile Results

### `mac_llm_A.v`

Exit status: 0

Verbatim compiler output:

```text
warning: Some design elements have no explicit time unit and/or
       : time precision. This may cause confusing timing results.
       : Affected design elements are:
       :   -- module mac declared here: mac_llm_A.v:1
```

### `mac_llm_B.v`

Exit status: 0

Verbatim compiler output:

```text
warning: Some design elements have no explicit time unit and/or
       : time precision. This may cause confusing timing results.
       : Affected design elements are:
       :   -- module mac declared here: mac_llm_B.v:1
```

## Simulation Results

The testbench applies `[a=3, b=4]` for 3 cycles, asserts synchronous reset, then applies `[a=-5, b=2]` for 2 cycles.

### `mac_llm_A.v`

```text
reset: out=0 expected=0
3*4 cycle 1: out=12 expected=12
3*4 cycle 2: out=24 expected=24
3*4 cycle 3: out=36 expected=36
reset between sequences: out=0 expected=0
-5*2 cycle 1: out=-10 expected=-10
-5*2 cycle 2: out=-20 expected=-20
PASS
```

### `mac_llm_B.v`

```text
reset: out=0 expected=0
3*4 cycle 1: out=12 expected=12
3*4 cycle 2: out=24 expected=24
3*4 cycle 3: out=36 expected=36
reset between sequences: out=0 expected=0
-5*2 cycle 1: out=-10 expected=-10
-5*2 cycle 2: out=-20 expected=-20
PASS
```

## Issues And Corrections

### Issue 1: `mac_llm_B.v` relies on implicit multiply sizing and extension

Offending line:

```systemverilog
out <= out + (a * b);
```

Why this is an issue: both operands are signed 8-bit values, but the multiply result is used directly inside a 32-bit accumulation expression. This passed the focused Icarus test, but it relies on expression sizing and sign-extension behavior instead of making the 16-bit product and 32-bit sign extension explicit. That is easy to misread and is a common source of simulator/synthesis mismatches in generated MAC code.

Corrected version:

```systemverilog
logic signed [15:0] product;
logic signed [31:0] product_ext;

assign product = a * b;
assign product_ext = {{16{product[15]}}, product};

always_ff @(posedge clk) begin
    if (rst) begin
        out <= 32'sd0;
    end else begin
        out <= out + product_ext;
    end
end
```

### Issue 2: `mac_llm_A.v` uses a terse sized cast for sign extension

Offending line:

```systemverilog
out <= out + 32'(product);
```

Why this is an issue: `32'(product)` is compact SystemVerilog syntax, but it is less explicit than a named 32-bit signed value. The assignment asks us to check sign extension carefully; making the sign-extension step visible improves reviewability and portability.

Corrected version:

```systemverilog
logic signed [15:0] product;
logic signed [31:0] product_ext;

assign product = a * b;
assign product_ext = {{16{product[15]}}, product};
out <= out + product_ext;
```

### Issue 3: both generated files omit an explicit time unit

Offending first line in each generated file:

```systemverilog
module mac (
```

Why this is an issue: Icarus reports a warning because `mac_tb.v` has a `timescale` but the generated DUT files do not. This does not change the MAC's synthesized logic, but adding a time unit removes confusing timing warnings during simulation.

Corrected version:

```systemverilog
`timescale 1ns/1ps

module mac (
```

## Corrected Implementation

The corrected implementation is in `hdl/mac_correct.v`. It compiles without warnings under:

```sh
iverilog -g2012 -Wall -o mac_correct_tb.vvp mac_correct.v mac_tb.v
```

Simulation output:

```text
reset: out=0 expected=0
3*4 cycle 1: out=12 expected=12
3*4 cycle 2: out=24 expected=24
3*4 cycle 3: out=36 expected=36
reset between sequences: out=0 expected=0
-5*2 cycle 1: out=-10 expected=-10
-5*2 cycle 2: out=-20 expected=-20
PASS
```

The exact assignment command:

```sh
yosys -p 'synth; stat' mac_correct.v
```

failed because Yosys parses `.v` as Verilog-2005 by default:

```text
Lexer warning: The SystemVerilog keyword `logic' (at mac_correct.v:4) is not recognized unless read_verilog is called with -sv!
mac_correct.v:4: ERROR: syntax error, unexpected TOK_ID, expecting ')' or ',' or '='
```

The SystemVerilog-enabled Yosys run passed:

```sh
yosys -p 'read_verilog -sv mac_correct.v; synth; stat'
```

Relevant Yosys output:

```text
=== mac ===

      832 wires
     1063 wire bits
        5 public wires
       50 public wire bits
        5 ports
       50 port bits
      885 cells
       17   $_ANDNOT_
      112   $_AND_
        3   $_MUX_
      355   $_NAND_
        2   $_NOR_
        1   $_NOT_
       31   $_ORNOT_
       23   $_OR_
       32   $_SDFF_PP0_
       98   $_XNOR_
      211   $_XOR_

Checking module mac...
Found and reported 0 problems.
```

Full logs are saved in `logs/mac_llm_A_compile.log`, `logs/mac_llm_A_sim.log`, `logs/mac_llm_B_compile.log`, `logs/mac_llm_B_sim.log`, `logs/mac_correct_compile.log`, `logs/mac_correct_sim.log`, `logs/mac_correct_yosys.log`, and `logs/mac_correct_yosys_assignment_cmd.log`.
