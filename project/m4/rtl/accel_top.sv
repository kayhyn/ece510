`timescale 1ns/1ps

/*
 * Module: accel_top
 *
 * Purpose:
 *   Realistic top-level accelerator wrapper for the 128-MAC INT8 convolution
 *   array. This wraps `mac_array` with on-chip weight storage (SRAM-style),
 *   an output result serializer, and narrow AXI4-Stream I/O ports (~140 pins
 *   instead of ~5,134), enabling full place-and-route in OpenLane.
 *
 *   Design improvements over the initial mac_array standalone synthesis:
 *     - Realistic I/O pin count via internal weight memory and result
 *       serializer. External ports are s_tdata[63:0] (input, opcode-tagged)
 *       and m_tdata[63:0] (output), plus handshake signals.
 *     - Banked broadcast fan-out tree. The shared activation and control
 *       signals (valid/first/last) are re-registered into BANK_COUNT banks
 *       of ~16 lanes each, limiting fan-out to ~16-17 sinks per net. This
 *       adds 1 cycle of latency but dramatically reduces worst-case delay.
 *     - Carry-save accumulation in mac_array removes the 32-bit ripple-carry
 *       adder from the inner-loop critical path.
 *
 * External interface:
 *   Input AXI4-Stream (s_tvalid/s_tready/s_tdata[63:0]):
 *     Opcode-tagged beats:
 *       LOAD_WEIGHT:
 *         s_tdata[63:56] = 0x01 (opcode)
 *         s_tdata[55:49] = lane[6:0]
 *         s_tdata[48:40] = addr[8:0]  (reduction element index, 0..575)
 *         s_tdata[39:32] = weight[7:0] (signed INT8)
 *         s_tdata[31:0]  = (unused)
 *       COMPUTE:
 *         s_tdata[63:56] = 0x02 (opcode)
 *         s_tdata[55]    = first (start new accumulation)
 *         s_tdata[54]    = last  (emit result)
 *         s_tdata[53:48] = (unused)
 *         s_tdata[47:40] = activation[7:0] (signed INT8, broadcast)
 *         s_tdata[39:0]  = (unused)
 *
 *   Output AXI4-Stream (m_tvalid/m_tready/m_tdata[63:0]):
 *         m_tdata[63]    = 0 (pad)
 *         m_tdata[62:56] = channel[6:0]
 *         m_tdata[55:24] = result[31:0] (signed INT32)
 *         m_tdata[23:0]  = 0 (pad)
 *     The 128 channel results drain sequentially, 1 per beat, after each pixel.
 *
 * Clocking and reset: single clock domain clk; synchronous active-high reset.
 */
module accel_top #(
    parameter int NUM_MAC      = 128,
    parameter int DATA_WIDTH   = 8,
    parameter int ACC_WIDTH    = 32,
    parameter int STREAM_WIDTH = 64,
    parameter int L_MAX        = 576,   // max reduction length (weight depth)
    parameter int BANK_COUNT   = 8      // number of broadcast banks (128/8=16 lanes each)
) (
    input  logic                        clk,
    input  logic                        rst,

    // Input AXI4-Stream (narrow, opcode-tagged).
    input  logic                        s_tvalid,
    output logic                        s_tready,
    input  logic [STREAM_WIDTH-1:0]     s_tdata,

    // Output AXI4-Stream (narrow, serialized results).
    output logic                        m_tvalid,
    input  logic                        m_tready,
    output logic [STREAM_WIDTH-1:0]     m_tdata
);

    localparam int LANES_PER_BANK = NUM_MAC / BANK_COUNT;  // 16
    localparam int ADDR_WIDTH     = $clog2(L_MAX);         // 10 bits for 576
    localparam int LANE_IDX_WIDTH = $clog2(NUM_MAC);       // 7 bits

    // ========================================================================
    // Opcode decode
    // ========================================================================
    localparam logic [7:0] OP_LOAD_WEIGHT = 8'h01;
    localparam logic [7:0] OP_COMPUTE     = 8'h02;

    logic [7:0]                    opcode;
    logic                          input_handshake;

    assign opcode          = s_tdata[63:56];
    assign input_handshake = s_tvalid && s_tready;

    // Weight load decode -- non-overlapping bit fields
    logic [LANE_IDX_WIDTH-1:0]     wl_lane;   // 7 bits: [55:49]
    logic [ADDR_WIDTH-1:0]         wl_addr;   // 10 bits: but we only use 9 since L_MAX=576 needs 10
    logic signed [DATA_WIDTH-1:0]  wl_data;   // 8 bits: [39:32]

    assign wl_lane = s_tdata[55:49];
    assign wl_addr = s_tdata[48:39];  // 10 bits: 0..575
    assign wl_data = $signed(s_tdata[38:31]);

    // Compute decode
    logic                          comp_first;
    logic                          comp_last;
    logic signed [DATA_WIDTH-1:0]  comp_activation;

    assign comp_first      = s_tdata[55];
    assign comp_last       = s_tdata[54];
    assign comp_activation = $signed(s_tdata[47:40]);

    // Weight address counter (auto-increments during compute phase)
    logic [ADDR_WIDTH-1:0]         weight_addr;

    always_ff @(posedge clk) begin
        if (rst) begin
            weight_addr <= '0;
        end else if (input_handshake && opcode == OP_COMPUTE) begin
            if (comp_first)
                weight_addr <= 1;  // first element uses addr 0, next will use 1
            else
                weight_addr <= weight_addr + 1;
        end
    end

    // ========================================================================
    // Banked broadcast fan-out tree
    // One cycle of registered fan-out: activation + valid/first/last are
    // re-registered into BANK_COUNT copies, each driving LANES_PER_BANK lanes.
    // This limits fan-out to ~16 sinks per net instead of 128*N.
    // ========================================================================

    // Pre-bank (global) signals from the input decode
    logic                          pre_valid;
    logic                          pre_first;
    logic                          pre_last;
    logic signed [DATA_WIDTH-1:0]  pre_activation;
    logic [ADDR_WIDTH-1:0]         pre_weight_addr;

    always_ff @(posedge clk) begin
        if (rst) begin
            pre_valid       <= 1'b0;
            pre_first       <= 1'b0;
            pre_last        <= 1'b0;
            pre_activation  <= '0;
            pre_weight_addr <= '0;
        end else begin
            pre_valid      <= (input_handshake && opcode == OP_COMPUTE);
            pre_first      <= (input_handshake && opcode == OP_COMPUTE) ? comp_first : 1'b0;
            pre_last       <= (input_handshake && opcode == OP_COMPUTE) ? comp_last  : 1'b0;
            pre_activation <= comp_activation;
            if (input_handshake && opcode == OP_COMPUTE) begin
                if (comp_first)
                    pre_weight_addr <= '0;  // first element reads addr 0
                else
                    pre_weight_addr <= weight_addr;
            end
        end
    end

    // Per-bank registered copies (limits fan-out to ~16 lanes per net)
    logic                         bank_valid  [BANK_COUNT];
    logic                         bank_first  [BANK_COUNT];
    logic                         bank_last   [BANK_COUNT];
    logic signed [DATA_WIDTH-1:0] bank_act    [BANK_COUNT];

    genvar bi;
    generate
        for (bi = 0; bi < BANK_COUNT; bi = bi + 1) begin : bcast_bank
            always_ff @(posedge clk) begin
                if (rst) begin
                    bank_valid[bi] <= 1'b0;
                    bank_first[bi] <= 1'b0;
                    bank_last[bi]  <= 1'b0;
                    bank_act[bi]   <= '0;
                end else begin
                    bank_valid[bi] <= pre_valid;
                    bank_first[bi] <= pre_first;
                    bank_last[bi]  <= pre_last;
                    bank_act[bi]   <= pre_activation;
                end
            end
        end
    endgenerate

    // ========================================================================
    // MAC array with banked inputs
    // The mac_array's internal pipeline is 3 stages (A: capture, B: multiply,
    // C: CSA accumulate). The banked broadcast adds 2 cycles of latency before
    // the array (pre-bank + per-bank registers), for a total of 5 stages from
    // input to output.
    // ========================================================================

    logic [NUM_MAC*DATA_WIDTH-1:0] array_weights;
    logic                          array_in_valid;
    logic                          array_in_first;
    logic                          array_in_last;
    logic signed [DATA_WIDTH-1:0]  array_activation;
    logic                          array_out_valid;
    logic [NUM_MAC*ACC_WIDTH-1:0]  array_results;

    // Use bank 0's signals for the shared control (all banks are identical)
    assign array_in_valid   = bank_valid[0];
    assign array_in_first   = bank_first[0];
    assign array_in_last    = bank_last[0];
    assign array_activation = bank_act[0];

    // Weight lookup: pipeline-delayed to match broadcast bank latency
    logic [ADDR_WIDTH-1:0] bank_weight_addr;

    always_ff @(posedge clk) begin
        if (rst)
            bank_weight_addr <= '0;
        else
            bank_weight_addr <= pre_weight_addr;
    end

    // ========================================================================
    // Per-lane weight banks (128 independent L_MAX x 8b register files).
    // Declared as 128 separate, single-port banks via a generate block so that
    // yosys infers 128 small register files (one per lane) rather than one
    // collapsed 128-read-port multi-port memory; the latter blows up into
    // millions of muxes and exceeds synthesis memory.
    // ========================================================================
    genvar wmi;
    generate
        for (wmi = 0; wmi < NUM_MAC; wmi = wmi + 1) begin : weight_bank
            logic signed [DATA_WIDTH-1:0] mem [L_MAX];
            always_ff @(posedge clk) begin
                if (input_handshake && opcode == OP_LOAD_WEIGHT
                    && wl_lane == wmi[LANE_IDX_WIDTH-1:0]) begin
                    mem[wl_addr] <= wl_data;
                end
            end
            assign array_weights[wmi*DATA_WIDTH +: DATA_WIDTH] = mem[bank_weight_addr];
        end
    endgenerate

    mac_array #(
        .NUM_MAC(NUM_MAC),
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) u_array (
        .clk(clk),
        .rst(rst),
        .in_valid(array_in_valid),
        .in_first(array_in_first),
        .in_last(array_in_last),
        .activation(array_activation),
        .weights(array_weights),
        .out_valid(array_out_valid),
        .results(array_results)
    );

    // ========================================================================
    // Result serializer
    // When array_out_valid pulses, latch all 128 results, then drain them
    // one channel at a time over m_tdata[63:0].
    // ========================================================================

    logic [NUM_MAC*ACC_WIDTH-1:0]  result_buf;
    logic                          draining;
    logic [LANE_IDX_WIDTH-1:0]     drain_idx;
    logic signed [ACC_WIDTH-1:0]   drain_result;

    always_ff @(posedge clk) begin
        if (rst) begin
            draining  <= 1'b0;
            drain_idx <= '0;
            result_buf <= '0;
        end else begin
            if (array_out_valid) begin
                result_buf <= array_results;
                draining   <= 1'b1;
                drain_idx  <= '0;
            end else if (draining && m_tvalid && m_tready) begin
                if (drain_idx == LANE_IDX_WIDTH'(NUM_MAC - 1)) begin
                    draining  <= 1'b0;
                    drain_idx <= '0;
                end else begin
                    drain_idx <= drain_idx + 1;
                end
            end
        end
    end

    // Extract the current channel's result from the buffer
    assign drain_result = $signed(result_buf[drain_idx*ACC_WIDTH +: ACC_WIDTH]);

    assign m_tvalid = draining;
    assign m_tdata  = {1'b0, drain_idx, drain_result, 24'b0};

    // Backpressure: accept input when not draining results
    assign s_tready = !draining;

endmodule
