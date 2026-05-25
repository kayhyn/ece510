`timescale 1ns/1ps

/*
 * Module: top
 *
 * Purpose:
 *   Milestone 3 integrated accelerator top. The module instantiates the M2
 *   AXI4-Stream interface (`axis_interface`) and the M2 INT8 dot-product
 *   compute core (`compute_core`) and connects them with command-decoding glue.
 *
 * External ports:
 *   clk           input   1 bit      System clock; all logic is single-domain.
 *   rst           input   1 bit      Synchronous active-high reset.
 *   s_axis_tdata  input   32 bits    Host command stream payload.
 *   s_axis_tvalid input   1 bit      Host command stream valid.
 *   s_axis_tready output  1 bit      Host command stream ready.
 *   s_axis_tlast  input   1 bit      Host command packet terminator.
 *   m_axis_tdata  output  32 bits    Host response stream payload.
 *   m_axis_tvalid output  1 bit      Host response stream valid.
 *   m_axis_tready input   1 bit      Host response stream ready.
 *   m_axis_tlast  output  1 bit      Host response packet terminator.
 *   compute_busy  output  1 bit      Debug/status: compute core is active.
 *   compute_done  output  1 bit      Debug/status: one-cycle result-valid pulse.
 *
 * Host command format:
 *   s_axis_tdata[31:28] = 4'h1 for all writes accepted by the M2 interface.
 *   s_axis_tdata[27:24] = M3 subcommand.
 *     4'h0: LOAD_ACTIVATION, payload[23:20] = tap index, payload[7:0] = INT8.
 *     4'h1: LOAD_WEIGHT,     payload[23:20] = tap index, payload[7:0] = INT8.
 *     4'h2: LOAD_BIAS_LO,    payload[15:0]  = bias[15:0].
 *     4'h3: LOAD_BIAS_HI,    payload[15:0]  = bias[31:16].
 *     4'h4: START, starts the 9-tap dot product when the core is idle.
 *     4'h5: READ_RESULT, emits {4'hB, result[27:0]} when result_valid is set.
 *
 * Glue logic:
 *   The M2 interface accepts and backpressures host writes. This top-level
 *   glue observes completed write handshakes, packs activation/weight/bias
 *   registers, pulses compute_core.start, latches compute_core.result, and
 *   muxes a one-word result response onto the host response stream.
 */
module top (
    input  logic        clk,
    input  logic        rst,
    input  logic [31:0] s_axis_tdata,
    input  logic        s_axis_tvalid,
    output logic        s_axis_tready,
    input  logic        s_axis_tlast,
    output logic [31:0] m_axis_tdata,
    output logic        m_axis_tvalid,
    input  logic        m_axis_tready,
    output logic        m_axis_tlast,
    output logic        compute_busy,
    output logic        compute_done
);

    localparam int TAPS = 9;
    localparam int DATA_WIDTH = 8;
    localparam int ACC_WIDTH = 32;

    localparam logic [3:0] OPCODE_WRITE_CONFIG = 4'h1;
    localparam logic [3:0] RESP_RESULT         = 4'hB;

    localparam logic [3:0] CMD_LOAD_ACTIVATION = 4'h0;
    localparam logic [3:0] CMD_LOAD_WEIGHT     = 4'h1;
    localparam logic [3:0] CMD_LOAD_BIAS_LO    = 4'h2;
    localparam logic [3:0] CMD_LOAD_BIAS_HI    = 4'h3;
    localparam logic [3:0] CMD_START           = 4'h4;
    localparam logic [3:0] CMD_READ_RESULT     = 4'h5;

    logic [31:0] interface_m_axis_tdata;
    logic        interface_m_axis_tvalid;
    logic        interface_m_axis_tlast;
    logic [27:0] interface_config_reg;

    logic signed [TAPS*DATA_WIDTH-1:0] activations;
    logic signed [TAPS*DATA_WIDTH-1:0] weights;
    logic signed [ACC_WIDTH-1:0]       bias;
    logic                              start;
    logic signed [ACC_WIDTH-1:0]       result;
    logic signed [ACC_WIDTH-1:0]       result_latched;
    logic                              result_valid;
    logic                              result_response_valid;

    logic command_handshake;
    logic [3:0] opcode;
    logic [3:0] subcommand;
    logic [3:0] tap_index;
    logic signed [7:0] data_byte;

    assign opcode = s_axis_tdata[31:28];
    assign subcommand = s_axis_tdata[27:24];
    assign tap_index = s_axis_tdata[23:20];
    assign data_byte = s_axis_tdata[7:0];
    assign command_handshake = s_axis_tvalid && s_axis_tready && s_axis_tlast &&
                               (opcode == OPCODE_WRITE_CONFIG);

    assign m_axis_tdata = result_response_valid ? {RESP_RESULT, result_latched[27:0]} :
                          interface_m_axis_tdata;
    assign m_axis_tvalid = result_response_valid || interface_m_axis_tvalid;
    assign m_axis_tlast = result_response_valid ? 1'b1 : interface_m_axis_tlast;

    axis_interface interface_i (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast(s_axis_tlast),
        .m_axis_tdata(interface_m_axis_tdata),
        .m_axis_tvalid(interface_m_axis_tvalid),
        .m_axis_tready(m_axis_tready && !result_response_valid),
        .m_axis_tlast(interface_m_axis_tlast),
        .config_reg(interface_config_reg)
    );

    compute_core #(
        .TAPS(TAPS),
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) compute_i (
        .clk(clk),
        .rst(rst),
        .start(start),
        .activations(activations),
        .weights(weights),
        .bias(bias),
        .busy(compute_busy),
        .done(compute_done),
        .result(result)
    );

    always_ff @(posedge clk) begin
        if (rst) begin
            activations <= '0;
            weights <= '0;
            bias <= '0;
            start <= 1'b0;
            result_latched <= '0;
            result_valid <= 1'b0;
            result_response_valid <= 1'b0;
        end else begin
            start <= 1'b0;

            if (compute_done) begin
                result_latched <= result;
                result_valid <= 1'b1;
            end

            if (result_response_valid && m_axis_tready) begin
                result_response_valid <= 1'b0;
            end

            if (command_handshake) begin
                case (subcommand)
                    CMD_LOAD_ACTIVATION: begin
                        if (tap_index < TAPS[3:0]) begin
                            activations[tap_index*DATA_WIDTH +: DATA_WIDTH] <= data_byte;
                        end
                    end

                    CMD_LOAD_WEIGHT: begin
                        if (tap_index < TAPS[3:0]) begin
                            weights[tap_index*DATA_WIDTH +: DATA_WIDTH] <= data_byte;
                        end
                    end

                    CMD_LOAD_BIAS_LO: begin
                        bias[15:0] <= s_axis_tdata[15:0];
                    end

                    CMD_LOAD_BIAS_HI: begin
                        bias[31:16] <= s_axis_tdata[15:0];
                    end

                    CMD_START: begin
                        if (!compute_busy) begin
                            start <= 1'b1;
                            result_valid <= 1'b0;
                        end
                    end

                    CMD_READ_RESULT: begin
                        if (result_valid && !result_response_valid) begin
                            result_response_valid <= 1'b1;
                        end
                    end

                    default: begin
                    end
                endcase
            end
        end
    end

endmodule
