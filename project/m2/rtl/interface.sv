`timescale 1ns/1ps

/*
 * Module: axis_interface
 *
 * Purpose:
 *   Minimal AXI4-Stream command/response interface for the M2 accelerator
 *   prototype. This module matches the M1-selected AXI4-Stream transport and
 *   demonstrates complete TVALID/TREADY write and read/response transactions.
 *
 * Clocking and reset:
 *   Single clock domain: clk.
 *   Reset is synchronous, active high.
 *
 * AXI4-Stream contract:
 *   A transfer occurs only when TVALID and TREADY are both high on a rising
 *   clk edge. Source-side payloads remain stable while TVALID is high and
 *   TREADY is low. This module deasserts s_axis_tready while a response is
 *   pending so no command is dropped.
 *
 * Transaction format:
 *   s_axis_tdata[31:28] = opcode
 *     4'h1: WRITE_CONFIG. s_axis_tdata[27:0] is stored in config_reg.
 *     4'h2: READ_CONFIG.  Emits one response word on m_axis_tdata.
 *   s_axis_tdata[27:0] = payload
 *   m_axis_tdata response = {4'hA, config_reg}
 *
 * Ports:
 *   clk           input   1 bit      System clock.
 *   rst           input   1 bit      Synchronous active-high reset.
 *   s_axis_tdata  input   32 bits    Command stream payload.
 *   s_axis_tvalid input   1 bit      Command stream valid.
 *   s_axis_tready output  1 bit      Command stream ready.
 *   s_axis_tlast  input   1 bit      Command packet terminator; single-word commands use 1.
 *   m_axis_tdata  output  32 bits    Response stream payload.
 *   m_axis_tvalid output  1 bit      Response stream valid.
 *   m_axis_tready input   1 bit      Response stream ready.
 *   m_axis_tlast  output  1 bit      Response packet terminator; responses are one word.
 *   config_reg    output  28 bits    Stored configuration payload for debug/status.
 */
module axis_interface (
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
    output logic [27:0] config_reg
);

    localparam logic [3:0] OPCODE_WRITE_CONFIG = 4'h1;
    localparam logic [3:0] OPCODE_READ_CONFIG  = 4'h2;
    localparam logic [3:0] OPCODE_RESPONSE     = 4'hA;

    logic [3:0] opcode;
    logic [27:0] payload;
    logic input_handshake;
    logic output_handshake;

    assign opcode = s_axis_tdata[31:28];
    assign payload = s_axis_tdata[27:0];
    assign s_axis_tready = !m_axis_tvalid;
    assign input_handshake = s_axis_tvalid && s_axis_tready;
    assign output_handshake = m_axis_tvalid && m_axis_tready;

    always_ff @(posedge clk) begin
        if (rst) begin
            config_reg <= 28'd0;
            m_axis_tdata <= 32'd0;
            m_axis_tvalid <= 1'b0;
            m_axis_tlast <= 1'b0;
        end else begin
            if (output_handshake) begin
                m_axis_tvalid <= 1'b0;
                m_axis_tlast <= 1'b0;
            end

            if (input_handshake && s_axis_tlast) begin
                if (opcode == OPCODE_WRITE_CONFIG) begin
                    config_reg <= payload;
                end else if (opcode == OPCODE_READ_CONFIG) begin
                    m_axis_tdata <= {OPCODE_RESPONSE, config_reg};
                    m_axis_tvalid <= 1'b1;
                    m_axis_tlast <= 1'b1;
                end
            end
        end
    end

endmodule
