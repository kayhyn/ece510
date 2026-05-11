`timescale 1ns/1ps

// 4x4 binary-weight crossbar MAC unit.
//
// Each cycle (when not in reset) the module computes a matrix-vector
// product:
//
//     out[j] = sum over i of  weight[i][j] * in[i]
//
// where every weight[i][j] is constrained to +1 or -1.  Weights are
// stored compactly in a register array using 1 bit per cell:
//
//     weight_bit = 0  ->  +1
//     weight_bit = 1  ->  -1
//
// The output port is sized like an accumulator so that wider sums fit
// without overflow if the parameters are scaled up later.

module crossbar_mac #(
    parameter int N         = 4,   // crossbar dimension (rows = cols)
    parameter int IN_WIDTH  = 8,   // signed input bit-width
    parameter int ACC_WIDTH = 16   // signed accumulator/output bit-width
) (
    input  logic                                clk,
    input  logic                                rst,      // sync, active high
    input  logic                                load_w,   // latch weight_in
    input  logic        [N*N-1:0]               weight_in,// flat 1-bit-per-cell
    input  logic signed [IN_WIDTH-1:0]          in_vec    [N],
    output logic signed [ACC_WIDTH-1:0]         out_vec   [N]
);

    // Weight register array, flattened to a packed vector so that
    // bit-select with non-constant indices is well supported.  Cell
    // (i, j) lives at bit  i*N + j.  Storage is N*N bits = 16 bits for
    // the default 4x4 crossbar.
    logic [N*N-1:0] weight;

    always_ff @(posedge clk) begin
        if (rst) begin
            weight <= '0;
        end else if (load_w) begin
            weight <= weight_in;
        end
    end

    // Combinational dot products per output column, registered into
    // out_vec on the next clock edge.
    logic signed [ACC_WIDTH-1:0] dot [N];

    always_comb begin
        logic signed [ACC_WIDTH-1:0] acc;
        logic signed [ACC_WIDTH-1:0] term;
        for (int j = 0; j < N; j++) begin
            acc = '0;
            for (int i = 0; i < N; i++) begin
                // Sign-extend the input to accumulator width, then add
                // or subtract based on the binary weight.  Subtraction
                // models multiply-by-minus-one without a multiplier.
                term = in_vec[i];
                if (weight[i*N + j])
                    acc = acc - term;
                else
                    acc = acc + term;
            end
            dot[j] = acc;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            for (int j = 0; j < N; j++) out_vec[j] <= '0;
        end else begin
            for (int j = 0; j < N; j++) out_vec[j] <= dot[j];
        end
    end

endmodule
