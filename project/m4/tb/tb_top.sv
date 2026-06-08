`timescale 1ns/1ps

/*
 * Final M4 production testbench.
 *
 * This testbench matches the synthesized accel_top configuration:
 *   - 128 INT8 MAC lanes
 *   - L_MAX=64 entries per lane
 *   - narrow 64-bit AXI4-Stream input/output
 *
 * The target convolution reduction is 576 elements, so the host executes nine
 * 64-element tiles and accumulates the nine returned partial sums. All traffic
 * passes through accel_top's production interface. The measured cycle count
 * includes weight loading, compute traffic, result serialization, and stalls.
 */
module tb_top;
    localparam int NUM_MAC      = 128;
    localparam int DATA_WIDTH   = 8;
    localparam int ACC_WIDTH    = 32;
    localparam int STREAM_WIDTH = 64;
    localparam int TILE_L       = 64;
    localparam int FULL_L       = 576;
    localparam int NUM_TILES    = FULL_L / TILE_L;
    localparam int N_PIX        = 8;
    localparam int BANK_COUNT   = 8;

    logic clk, rst;
    logic                    s_tvalid, s_tready;
    logic [STREAM_WIDTH-1:0] s_tdata;
    logic                    m_tvalid, m_tready;
    logic [STREAM_WIDTH-1:0] m_tdata;

    logic signed [DATA_WIDTH-1:0] act_mem [N_PIX][FULL_L];
    logic signed [DATA_WIDTH-1:0] w_mem   [NUM_MAC][FULL_L];
    logic signed [ACC_WIDTH-1:0]  expected_partial[NUM_TILES][N_PIX][NUM_MAC];
    logic signed [ACC_WIDTH-1:0]  expected_full[N_PIX][NUM_MAC];
    logic signed [ACC_WIDTH-1:0]  host_accum[N_PIX][NUM_MAC];

    integer tile, p, j, c;
    integer tile_captured, pix_captured, ch_captured, tile_pixels_completed;
    integer partial_errors, full_errors;
    integer backpressure_cycles, backpressure_errors;
    logic backpressure_test_done;
    logic [STREAM_WIDTH-1:0] held_backpressure_data;
    longint cycle_count, start_cycle, end_cycle, total_cycles;
    longint total_macs;
    longint weight_load_beats, compute_beats, drain_beats;

    accel_top #(
        .NUM_MAC(NUM_MAC),
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH(ACC_WIDTH),
        .STREAM_WIDTH(STREAM_WIDTH),
        .L_MAX(TILE_L),
        .BANK_COUNT(BANK_COUNT)
    ) dut (
        .clk(clk),
        .rst(rst),
        .s_tvalid(s_tvalid),
        .s_tready(s_tready),
        .s_tdata(s_tdata),
        .m_tvalid(m_tvalid),
        .m_tready(m_tready),
        .m_tdata(m_tdata)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial cycle_count = 0;
    always @(posedge clk) cycle_count = cycle_count + 1;

    task automatic build_vectors;
        integer base;
        begin
            for (p = 0; p < N_PIX; p = p + 1)
                for (j = 0; j < FULL_L; j = j + 1)
                    if (p == 0)
                        act_mem[p][j] = (j % 2 == 0) ? 127 : -128;
                    else
                        act_mem[p][j] = (((p*3 + j) % 5) - 2);

            for (c = 0; c < NUM_MAC; c = c + 1)
                for (j = 0; j < FULL_L; j = j + 1)
                    if (c == 0)
                        w_mem[c][j] = (j % 2 == 0) ? -128 : 127;
                    else
                        w_mem[c][j] = (((c + j) % 7) - 3);

            for (p = 0; p < N_PIX; p = p + 1)
                for (c = 0; c < NUM_MAC; c = c + 1) begin
                    expected_full[p][c] = '0;
                    host_accum[p][c] = '0;
                    for (tile = 0; tile < NUM_TILES; tile = tile + 1) begin
                        expected_partial[tile][p][c] = '0;
                        base = tile * TILE_L;
                        for (j = 0; j < TILE_L; j = j + 1)
                            expected_partial[tile][p][c] =
                                expected_partial[tile][p][c]
                                + (act_mem[p][base+j] * w_mem[c][base+j]);
                        expected_full[p][c] = expected_full[p][c]
                            + expected_partial[tile][p][c];
                    end
                end
        end
    endtask

    task automatic send_beat(input logic [STREAM_WIDTH-1:0] beat);
        begin
            @(negedge clk);
            s_tvalid = 1'b1;
            s_tdata = beat;
            @(posedge clk);
            while (!s_tready)
                @(posedge clk);
        end
    endtask

    logic [6:0] cap_ch;
    logic signed [ACC_WIDTH-1:0] cap_result;

    always @(posedge clk) begin
        if (m_tvalid && m_tready && !rst) begin
            cap_ch = m_tdata[62:56];
            cap_result = $signed(m_tdata[55:24]);

            if (cap_ch != ch_captured[6:0]) begin
                partial_errors = partial_errors + 1;
                if (partial_errors <= 5)
                    $display("ORDER MISMATCH tile=%0d pix=%0d expected_ch=%0d got_ch=%0d",
                             tile_captured, pix_captured, ch_captured, cap_ch);
            end else begin
                if (cap_result !== expected_partial[tile_captured][pix_captured][cap_ch]) begin
                    partial_errors = partial_errors + 1;
                    if (partial_errors <= 5)
                        $display("PARTIAL MISMATCH tile=%0d pix=%0d ch=%0d got=%0d exp=%0d",
                                 tile_captured, pix_captured, cap_ch, cap_result,
                                 expected_partial[tile_captured][pix_captured][cap_ch]);
                end
                host_accum[pix_captured][cap_ch] =
                    host_accum[pix_captured][cap_ch] + cap_result;
            end

            if (ch_captured == NUM_MAC - 1) begin
                ch_captured = 0;
                tile_pixels_completed = tile_pixels_completed + 1;
                if (pix_captured == N_PIX - 1) begin
                    pix_captured = 0;
                    tile_captured = tile_captured + 1;
                end else begin
                    pix_captured = pix_captured + 1;
                end
            end else begin
                ch_captured = ch_captured + 1;
            end
        end
    end

    // Exercise output backpressure once. The serializer must hold the current
    // channel/result stable while m_tready is low, then resume in order.
    always @(negedge clk) begin
        if (!rst && m_tvalid && !backpressure_test_done) begin
            held_backpressure_data = m_tdata;
            m_tready = 1'b0;
            repeat (3) begin
                @(negedge clk);
                backpressure_cycles = backpressure_cycles + 1;
                if (!m_tvalid || m_tdata !== held_backpressure_data)
                    backpressure_errors = backpressure_errors + 1;
            end
            m_tready = 1'b1;
            backpressure_test_done = 1'b1;
        end
    end

    logic [STREAM_WIDTH-1:0] beat;
    integer base;

    initial begin
        $dumpfile("project/m4/sim/final_top.vcd");
        $dumpvars(0, clk, rst, s_tvalid, s_tready, m_tvalid, m_tready,
                  dut.opcode, dut.comp_first, dut.comp_last,
                  dut.array_in_valid, dut.array_in_first, dut.array_in_last,
                  dut.array_out_valid, dut.draining);

        rst = 1'b1;
        s_tvalid = 1'b0;
        s_tdata = '0;
        m_tready = 1'b1;
        backpressure_cycles = 0;
        backpressure_errors = 0;
        backpressure_test_done = 1'b0;
        held_backpressure_data = '0;
        tile_captured = 0;
        pix_captured = 0;
        ch_captured = 0;
        tile_pixels_completed = 0;
        partial_errors = 0;
        full_errors = 0;
        build_vectors();

        weight_load_beats = longint'(NUM_TILES) * longint'(NUM_MAC) * longint'(TILE_L);
        compute_beats = longint'(NUM_TILES) * longint'(N_PIX) * longint'(TILE_L);
        drain_beats = longint'(NUM_TILES) * longint'(N_PIX) * longint'(NUM_MAC);
        total_macs = longint'(N_PIX) * longint'(FULL_L) * longint'(NUM_MAC);

        repeat (5) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        start_cycle = cycle_count;

        for (tile = 0; tile < NUM_TILES; tile = tile + 1) begin
            base = tile * TILE_L;

            // Load this tile's 64 weights into every lane.
            for (c = 0; c < NUM_MAC; c = c + 1)
                for (j = 0; j < TILE_L; j = j + 1) begin
                    beat = '0;
                    beat[63:56] = 8'h01;
                    beat[55:49] = c[6:0];
                    beat[48:39] = j[9:0];
                    beat[38:31] = w_mem[c][base+j];
                    send_beat(beat);
                end

            // Compute every representative pixel for this tile.
            for (p = 0; p < N_PIX; p = p + 1) begin
                for (j = 0; j < TILE_L; j = j + 1) begin
                    beat = '0;
                    beat[63:56] = 8'h02;
                    beat[55] = (j == 0);
                    beat[54] = (j == TILE_L-1);
                    beat[47:40] = act_mem[p][base+j];
                    send_beat(beat);
                end
                @(negedge clk);
                s_tvalid = 1'b0;
                s_tdata = '0;
                // accel_top has one result buffer. Wait for all 128 serialized
                // channels before allowing the next tile result to reach it.
                while (tile_pixels_completed < tile*N_PIX + p + 1)
                    @(negedge clk);
            end

            // Weight memory is reused only after this tile's results drain.
            while (tile_captured < tile + 1)
                @(negedge clk);
        end

        @(negedge clk);
        s_tvalid = 1'b0;
        s_tdata = '0;
        end_cycle = cycle_count;
        total_cycles = end_cycle - start_cycle;

        for (p = 0; p < N_PIX; p = p + 1)
            for (c = 0; c < NUM_MAC; c = c + 1)
                if (host_accum[p][c] !== expected_full[p][c]) begin
                    full_errors = full_errors + 1;
                    if (full_errors <= 5)
                        $display("FULL MISMATCH pix=%0d ch=%0d got=%0d exp=%0d",
                                 p, c, host_accum[p][c], expected_full[p][c]);
                end

        $display("M4 FINAL PRODUCTION TILED BENCH ---------------------------");
        $display("  NUM_MAC=%0d TILE_L=%0d NUM_TILES=%0d FULL_L=%0d N_PIX=%0d",
                 NUM_MAC, TILE_L, NUM_TILES, FULL_L, N_PIX);
        $display("  partial_results_checked=%0d full_results_checked=%0d",
                 NUM_TILES*N_PIX*NUM_MAC, N_PIX*NUM_MAC);
        $display("  partial_errors=%0d full_errors=%0d", partial_errors, full_errors);
        $display("  total_macs=%0d", total_macs);
        $display("  weight_load_beats=%0d compute_beats=%0d drain_beats=%0d",
                 weight_load_beats, compute_beats, drain_beats);
        $display("  total_cycles=%0d (includes weight load, compute, serialization, stalls)",
                 total_cycles);
        $display("  backpressure_cycles=%0d backpressure_errors=%0d unstalled_schedule_cycles=%0d",
                 backpressure_cycles, backpressure_errors,
                 total_cycles - backpressure_cycles);
        $display("  useful_macs_per_total_cycle=%0d.%03d",
                 total_macs / total_cycles,
                 ((total_macs * 1000) / total_cycles) % 1000);

        if (partial_errors == 0 && full_errors == 0
            && backpressure_test_done && backpressure_errors == 0)
            $display("PASS: final synthesized-config accel_top tiled 576-element reduction");
        else
            $display("FAIL: final production tiled bench");
        $finish;
    end
endmodule
