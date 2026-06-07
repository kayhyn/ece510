`timescale 1ns/1ps

/*
 * Module: top
 *
 * Purpose:
 *   Milestone 4 integrated accelerator top. It wires the AXI4-Stream streaming
 *   interface (`stream_if`) to the 128-MAC INT8 compute core (`compute_core`,
 *   which wraps `mac_array`). This is the full integration of the project's
 *   planned datapath: the host streams one reduction element per cycle into the
 *   array through the input stream, the array sustains NUM_MAC MACs/cycle, and
 *   each completed output pixel's 128 channel results drain on the output stream.
 *
 *   This is the M4 scale-up of the M3 `top` (which integrated the single 9-tap
 *   M2 lane behind a single-word AXI4-Stream command interface). The compute
 *   core grows from 1 lane to 128 parallel lanes and the interface widens from a
 *   one-operand-per-transaction command port to a full streaming-data port.
 *
 * Ports: see stream_if for the AXI4-Stream input/output semantics.
 *
 * Clocking and reset: single clock domain clk; synchronous active-high reset.
 */
module top #(
    parameter int NUM_MAC    = 128,
    parameter int DATA_WIDTH = 8,
    parameter int ACC_WIDTH  = 32
) (
    input  logic                                 clk,
    input  logic                                 rst,

    // Input AXI4-Stream: one reduction element per beat.
    input  logic                                 s_tvalid,
    output logic                                 s_tready,
    input  logic                                 s_first,
    input  logic                                 s_last,
    input  logic signed [DATA_WIDTH-1:0]         s_activation,
    input  logic        [NUM_MAC*DATA_WIDTH-1:0] s_weights,

    // Output AXI4-Stream: one 128-channel pixel result per beat.
    output logic                                 m_tvalid,
    input  logic                                 m_tready,
    output logic        [NUM_MAC*ACC_WIDTH-1:0]  m_results
);

    logic                                 core_in_valid;
    logic                                 core_in_first;
    logic                                 core_in_last;
    logic signed [DATA_WIDTH-1:0]         core_activation;
    logic        [NUM_MAC*DATA_WIDTH-1:0] core_weights;
    logic                                 core_out_valid;
    logic        [NUM_MAC*ACC_WIDTH-1:0]  core_results;

    stream_if #(
        .NUM_MAC(NUM_MAC),
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) u_if (
        .clk(clk),
        .rst(rst),
        .s_tvalid(s_tvalid),
        .s_tready(s_tready),
        .s_first(s_first),
        .s_last(s_last),
        .s_activation(s_activation),
        .s_weights(s_weights),
        .m_tvalid(m_tvalid),
        .m_tready(m_tready),
        .m_results(m_results),
        .core_in_valid(core_in_valid),
        .core_in_first(core_in_first),
        .core_in_last(core_in_last),
        .core_activation(core_activation),
        .core_weights(core_weights),
        .core_out_valid(core_out_valid),
        .core_results(core_results)
    );

    compute_core #(
        .NUM_MAC(NUM_MAC),
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) u_core (
        .clk(clk),
        .rst(rst),
        .in_valid(core_in_valid),
        .in_first(core_in_first),
        .in_last(core_in_last),
        .activation(core_activation),
        .weights(core_weights),
        .out_valid(core_out_valid),
        .results(core_results)
    );

endmodule
