`timescale 1ns/1ps

/*
 * Module: mac_array
 *
 * Purpose:
 *   Milestone 4 parallel INT8 multiply-accumulate array. This is the scaled-up
 *   version of the M2/M3 single 9-tap `compute_core` lane: it instantiates
 *   NUM_MAC (default 128) MAC lanes that share one broadcast activation and
 *   each hold their own weight, so the array sustains NUM_MAC MACs per cycle.
 *
 *   This realizes the project's planned "128 INT8 MAC units @ 250 MHz, 64 GOPS"
 *   datapath. It maps directly to the dominant 3x3 INT8 convolution: each lane
 *   computes one output channel, the broadcast activation is the shared input
 *   patch element, and the per-lane weight is that channel's filter tap. A full
 *   output pixel streams its K = Kh*Kw*Cin = 576 reduction elements through the
 *   array; the 128 lanes produce 128 output channels in parallel.
 *
 * Dataflow (output-stationary, weight-streaming):
 *   One reduction element per cycle is presented on the streaming inputs:
 *     activation : shared INT8 input sample (broadcast to all lanes)
 *     weights    : NUM_MAC packed INT8 weights, lane i uses slice i
 *     in_valid   : element is valid this cycle
 *     in_first   : element is the first of a new accumulation (clears acc)
 *     in_last    : element is the last of the accumulation (emits result)
 *   Accumulations for back-to-back pixels may be streamed with no gap.
 *
 * Pipeline (3 stages; removes the M3 critical path's mux + serial mul/add):
 *   Stage A  capture activation/weights and the valid/first/last tags
 *   Stage B  signed 8x8 -> 16b multiply, registered
 *   Stage C  sign-extend to ACC_WIDTH and accumulate; emit on tagged-last
 *   Latency from a last element to out_valid = 3 cycles; throughput = 1 elem/cyc.
 *
 * Implementation note:
 *   The shared control pipeline (valid/first/last tags and the broadcast
 *   activation) is one always_ff block; the NUM_MAC data lanes are emitted via
 *   a genvar generate loop so each lane's registers are distinct elaborated
 *   signals (Verilator-clean, no runtime-indexed nonblocking array writes).
 *
 * Clocking and reset:
 *   Single clock domain clk. Synchronous active-high reset.
 *
 * Ports:
 *   clk        input   1 bit                       System clock.
 *   rst        input   1 bit                       Synchronous active-high reset.
 *   in_valid   input   1 bit                       Reduction element valid.
 *   in_first   input   1 bit                       First element of accumulation.
 *   in_last    input   1 bit                       Last element of accumulation.
 *   activation input   DATA_WIDTH (signed)         Broadcast INT8 activation.
 *   weights    input   NUM_MAC*DATA_WIDTH          Packed signed INT8 weights.
 *   out_valid  output  1 bit                       One-cycle results-valid pulse.
 *   results    output  NUM_MAC*ACC_WIDTH           Packed signed INT32 results.
 */
module mac_array #(
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

    localparam int PROD_WIDTH = 2 * DATA_WIDTH;

    // Shared control/datapath pipeline registers (not per-lane).
    logic                         a_valid, a_first, a_last;
    logic                         b_valid, b_first, b_last;
    logic signed [DATA_WIDTH-1:0] a_act;

    always_ff @(posedge clk) begin
        if (rst) begin
            a_valid   <= 1'b0;
            a_first   <= 1'b0;
            a_last    <= 1'b0;
            a_act     <= '0;
            b_valid   <= 1'b0;
            b_first   <= 1'b0;
            b_last    <= 1'b0;
            out_valid <= 1'b0;
        end else begin
            // Stage A capture
            a_valid <= in_valid;
            a_first <= in_first;
            a_last  <= in_last;
            a_act   <= activation;
            // Stage B tag propagation
            b_valid <= a_valid;
            b_first <= a_first;
            b_last  <= a_last;
            // Stage C emit pulse
            out_valid <= (b_valid && b_last);
        end
    end

    // Per-lane datapath: one MAC lane per output channel.
    genvar gi;
    generate
        for (gi = 0; gi < NUM_MAC; gi = gi + 1) begin : lane
            logic signed [DATA_WIDTH-1:0] aw;       // Stage A weight
            logic signed [PROD_WIDTH-1:0] bprod;    // Stage B product
            logic signed [ACC_WIDTH-1:0]  acc;      // Stage C accumulator

            logic signed [ACC_WIDTH-1:0]  prod_ext;
            logic signed [ACC_WIDTH-1:0]  acc_next;

            always_ff @(posedge clk) begin
                if (rst) begin
                    aw    <= '0;
                    bprod <= '0;
                    acc   <= '0;
                    results[gi*ACC_WIDTH +: ACC_WIDTH] <= '0;
                end else begin
                    // Stage A: capture this lane's weight
                    aw    <= $signed(weights[gi*DATA_WIDTH +: DATA_WIDTH]);
                    // Stage B: multiply Stage-A operands
                    bprod <= a_act * aw;
                    // Stage C: accumulate / emit
                    if (b_valid) begin
                        prod_ext = {{(ACC_WIDTH-PROD_WIDTH){bprod[PROD_WIDTH-1]}}, bprod};
                        acc_next = b_first ? prod_ext : (acc + prod_ext);
                        acc <= acc_next;
                        if (b_last) begin
                            results[gi*ACC_WIDTH +: ACC_WIDTH] <= acc_next;
                        end
                    end
                end
            end
        end
    endgenerate

endmodule
