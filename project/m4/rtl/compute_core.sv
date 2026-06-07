`timescale 1ns/1ps

/*
 * Module: compute_core
 *
 * Purpose:
 *   Named compute core of the M4 accelerator. The compute core is the project's
 *   128-MAC INT8 array (`mac_array`); this module is the thin, parameterized
 *   boundary that `top` instantiates so the integration hierarchy matches the
 *   M2/M3 lineage (interface + compute core + top). It adds no logic of its own
 *   and introduces no extra registers: it forwards the streaming ports straight
 *   to `mac_array`, so the synthesized/benchmarked datapath is exactly the array
 *   reported in project/m4/synth/.
 *
 *   The standalone OpenLane 2 synthesis run (project/m4/synth/config.json)
 *   targets `mac_array` directly; this wrapper exists for the integrated
 *   top-level simulation and for naming clarity, and is logically transparent.
 *
 * Clocking and reset: single clock domain clk; synchronous active-high reset.
 */
module compute_core #(
    parameter int NUM_MAC    = 128,
    parameter int DATA_WIDTH = 8,
    parameter int ACC_WIDTH  = 32
) (
    input  logic                                 clk,
    input  logic                                 rst,
    input  logic                                 in_valid,
    input  logic                                 in_first,
    input  logic                                 in_last,
    input  logic signed [DATA_WIDTH-1:0]         activation,
    input  logic        [NUM_MAC*DATA_WIDTH-1:0] weights,
    output logic                                 out_valid,
    output logic        [NUM_MAC*ACC_WIDTH-1:0]  results
);

    mac_array #(
        .NUM_MAC(NUM_MAC),
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) u_array (
        .clk(clk),
        .rst(rst),
        .in_valid(in_valid),
        .in_first(in_first),
        .in_last(in_last),
        .activation(activation),
        .weights(weights),
        .out_valid(out_valid),
        .results(results)
    );

endmodule
