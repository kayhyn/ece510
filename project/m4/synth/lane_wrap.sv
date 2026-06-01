`timescale 1ns/1ps

/*
 * Module: lane_wrap
 *
 * Purpose:
 *   Single-lane (NUM_MAC=1) instance of the M4 `mac_array` used to obtain a
 *   real placed-and-routed Fmax for the pipelined MAC *datapath* (the 8x8
 *   multiply stage and the 32-bit accumulate stage). The 128-lane array shares
 *   this exact per-lane logic; its only additional timing element is the
 *   broadcast buffer/clock tree for the shared activation+control nets, which
 *   is a place-and-route fixup rather than a logic-depth change. So this lane's
 *   PnR Fmax is the datapath ceiling the array converges to once those nets are
 *   buffered. It also keeps the I/O pin count small enough to place and route.
 */
module lane_wrap (
    input  logic              clk,
    input  logic              rst,
    input  logic              in_valid,
    input  logic              in_first,
    input  logic              in_last,
    input  logic signed [7:0] activation,
    input  logic        [7:0] weight,
    output logic              out_valid,
    output logic       [31:0] result
);
    mac_array #(.NUM_MAC(1), .DATA_WIDTH(8), .ACC_WIDTH(32)) u_lane (
        .clk(clk), .rst(rst),
        .in_valid(in_valid), .in_first(in_first), .in_last(in_last),
        .activation(activation),
        .weights(weight),
        .out_valid(out_valid),
        .results(result)
    );
endmodule
