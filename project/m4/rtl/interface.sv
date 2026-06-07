`timescale 1ns/1ps

/*
 * Module: stream_if
 *
 * Purpose:
 *   AXI4-Stream-style streaming interface for the M4 128-MAC array. This is the
 *   M1-selected AXI4-Stream transport, realized for the parallel array: it
 *   accepts one reduction-element beat per cycle on an input stream and drains
 *   one 128-channel output-pixel result on an output stream. It replaces the
 *   M2/M3 single-word AXI4-Stream command interface (`axis_interface`), which
 *   moved one INT8 operand per transaction, with a wide streaming-data interface
 *   sized to feed all 128 lanes in parallel.
 *
 * Input stream (host -> accelerator), one reduction element per beat:
 *   s_tvalid     beat valid
 *   s_tready     accelerator ready (driven high while no output is stalled)
 *   s_first      this element starts a new accumulation (maps to in_first)
 *   s_last       this element ends the accumulation (maps to in_last)
 *   s_activation broadcast INT8 activation for this element
 *   s_weights    NUM_MAC packed INT8 weights (one per output channel)
 *
 * Output stream (accelerator -> host), one 128-channel result per beat:
 *   m_tvalid     result beat valid
 *   m_tready     host ready
 *   m_results    NUM_MAC packed signed INT32 channel results
 *
 * A transfer occurs only when TVALID and TREADY are both high on a rising clk
 * edge, matching the AXI4-Stream handshake contract. The input is registered
 * once (one cycle of latency, no throughput loss) before being presented to the
 * compute core; the output is held until the host accepts it.
 *
 * Clocking and reset: single clock domain clk; synchronous active-high reset.
 */
module stream_if #(
    parameter int NUM_MAC    = 128,
    parameter int DATA_WIDTH = 8,
    parameter int ACC_WIDTH  = 32
) (
    input  logic                                 clk,
    input  logic                                 rst,

    // Input AXI4-Stream (one reduction element per beat).
    input  logic                                 s_tvalid,
    output logic                                 s_tready,
    input  logic                                 s_first,
    input  logic                                 s_last,
    input  logic signed [DATA_WIDTH-1:0]         s_activation,
    input  logic        [NUM_MAC*DATA_WIDTH-1:0] s_weights,

    // Output AXI4-Stream (one 128-channel result per beat).
    output logic                                 m_tvalid,
    input  logic                                 m_tready,
    output logic        [NUM_MAC*ACC_WIDTH-1:0]  m_results,

    // To/from the compute core (mac_array).
    output logic                                 core_in_valid,
    output logic                                 core_in_first,
    output logic                                 core_in_last,
    output logic signed [DATA_WIDTH-1:0]         core_activation,
    output logic        [NUM_MAC*DATA_WIDTH-1:0] core_weights,
    input  logic                                 core_out_valid,
    input  logic        [NUM_MAC*ACC_WIDTH-1:0]  core_results
);

    // Accept input whenever the output register is free. The single-pixel
    // output holding register is drained in one cycle by m_tready, so under a
    // host that keeps m_tready high this never backpressures the stream.
    assign s_tready = !(m_tvalid && !m_tready);

    logic input_handshake;
    assign input_handshake = s_tvalid && s_tready;

    // Registered input beat -> compute core stimulus (1-cycle latency).
    always_ff @(posedge clk) begin
        if (rst) begin
            core_in_valid   <= 1'b0;
            core_in_first   <= 1'b0;
            core_in_last    <= 1'b0;
            core_activation <= '0;
            core_weights    <= '0;
        end else begin
            core_in_valid   <= input_handshake;
            core_in_first   <= input_handshake ? s_first : 1'b0;
            core_in_last    <= input_handshake ? s_last  : 1'b0;
            core_activation <= s_activation;
            core_weights    <= s_weights;
        end
    end

    // Output holding register: latch a completed pixel, present until accepted.
    always_ff @(posedge clk) begin
        if (rst) begin
            m_tvalid  <= 1'b0;
            m_results <= '0;
        end else begin
            if (m_tvalid && m_tready) begin
                m_tvalid <= 1'b0;
            end
            if (core_out_valid) begin
                m_results <= core_results;
                m_tvalid  <= 1'b1;
            end
        end
    end

endmodule
