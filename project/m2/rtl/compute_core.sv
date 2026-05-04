`timescale 1ns/1ps

/*
 * Module: compute_core
 *
 * Purpose:
 *   Multi-cycle INT8 dot-product compute block for the project accelerator's
 *   dominant 3x3 convolution kernel. The M2 core models one 3x3 lane
 *   (9 activation/weight products) with INT32 accumulation.
 *
 * Clocking and reset:
 *   Single clock domain: clk.
 *   Reset is synchronous, active high.
 *
 * Ports:
 *   clk          input   1 bit               System clock.
 *   rst          input   1 bit               Synchronous active-high reset.
 *   start        input   1 bit               Pulse high for one cycle to start.
 *   activations  input   TAPS*DATA_WIDTH     Packed signed INT8 activations.
 *   weights      input   TAPS*DATA_WIDTH     Packed signed INT8 weights.
 *   bias         input   ACC_WIDTH           Signed INT32 initial accumulator.
 *   busy         output  1 bit               High while products are accumulated.
 *   done         output  1 bit               One-cycle pulse when result is valid.
 *   result       output  ACC_WIDTH           Signed INT32 dot-product result.
 */
module compute_core #(
    parameter int TAPS = 9,
    parameter int DATA_WIDTH = 8,
    parameter int ACC_WIDTH = 32
) (
    input  logic                                  clk,
    input  logic                                  rst,
    input  logic                                  start,
    input  logic signed [TAPS*DATA_WIDTH-1:0]    activations,
    input  logic signed [TAPS*DATA_WIDTH-1:0]    weights,
    input  logic signed [ACC_WIDTH-1:0]          bias,
    output logic                                  busy,
    output logic                                  done,
    output logic signed [ACC_WIDTH-1:0]          result
);

    localparam int TAP_INDEX_WIDTH = (TAPS <= 1) ? 1 : $clog2(TAPS);

    logic [TAP_INDEX_WIDTH-1:0] tap_index;
    logic signed [ACC_WIDTH-1:0] accumulator;
    logic signed [DATA_WIDTH-1:0] activation_tap;
    logic signed [DATA_WIDTH-1:0] weight_tap;
    logic signed [(2*DATA_WIDTH)-1:0] product;
    logic signed [ACC_WIDTH-1:0] product_ext;
    logic signed [ACC_WIDTH-1:0] next_accumulator;

    assign activation_tap = activations[tap_index*DATA_WIDTH +: DATA_WIDTH];
    assign weight_tap = weights[tap_index*DATA_WIDTH +: DATA_WIDTH];
    assign product = activation_tap * weight_tap;
    assign product_ext = {{(ACC_WIDTH-(2*DATA_WIDTH)){product[(2*DATA_WIDTH)-1]}}, product};
    assign next_accumulator = accumulator + product_ext;

    always_ff @(posedge clk) begin
        if (rst) begin
            tap_index <= '0;
            accumulator <= '0;
            result <= '0;
            busy <= 1'b0;
            done <= 1'b0;
        end else begin
            done <= 1'b0;

            if (start && !busy) begin
                tap_index <= '0;
                accumulator <= bias;
                busy <= 1'b1;
            end else if (busy) begin
                accumulator <= next_accumulator;

                if (tap_index == TAPS-1) begin
                    result <= next_accumulator;
                    busy <= 1'b0;
                    done <= 1'b1;
                end else begin
                    tap_index <= tap_index + 1'b1;
                end
            end
        end
    end

endmodule
