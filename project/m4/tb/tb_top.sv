`timescale 1ns/1ps

/*
 * Testbench: tb_top
 *
 * Final M4 end-to-end testbench. It drives the integrated accelerator `top`
 * (AXI4-Stream `stream_if` -> `compute_core` -> `mac_array`) entirely through
 * the host-side AXI4-Stream ports -- it never pokes the array directly.
 *
 * Workload: a representative slice of the dominant 3x3 INT8 convolution. The TB
 * streams N_PIX output pixels; each pixel reduces over L = Kh*Kw*Cin = 576
 * elements (the full 3x3x64 window). The 128 lanes compute 128 output channels
 * in parallel. Activations are broadcast across channels (as in convolution);
 * weights are reused unchanged across all pixels (weight reuse). Beats are
 * streamed back-to-back with s_tvalid held high and the host holding m_tready
 * high, so the measured cycle count reflects sustained steady-state throughput.
 *
 * Checks: an independent SystemVerilog reference recomputes every pixel/channel
 * result and compares against the streamed outputs. Reports total cycles for the
 * streamed region and the sustained MACs/cycle, which the benchmark extrapolates
 * to the full 2704-pixel layer at the synthesized clock.
 */
module tb_top;
    localparam int NUM_MAC    = 128;
    localparam int DATA_WIDTH = 8;
    localparam int ACC_WIDTH  = 32;
    localparam int L          = 576;   // Kh*Kw*Cin reduction length per pixel
    localparam int N_PIX      = 8;     // representative number of output pixels

    logic clk, rst;
    logic s_tvalid, s_tready, s_first, s_last;
    logic signed [DATA_WIDTH-1:0]         s_activation;
    logic        [NUM_MAC*DATA_WIDTH-1:0] s_weights;
    logic                                 m_tvalid, m_tready;
    logic        [NUM_MAC*ACC_WIDTH-1:0]  m_results;

    // Waveform monitor taps (1- and 32-bit) for a readable annotated figure.
    logic signed [DATA_WIDTH-1:0] mon_act;
    logic signed [ACC_WIDTH-1:0]  mon_res0;
    assign mon_act  = s_activation;
    assign mon_res0 = $signed(m_results[ACC_WIDTH-1:0]);

    // Stimulus storage
    logic signed [DATA_WIDTH-1:0] act_mem [N_PIX][L];   // per-pixel activations
    logic signed [DATA_WIDTH-1:0] w_mem   [NUM_MAC][L]; // per-channel weights (reused)
    logic signed [ACC_WIDTH-1:0]  expected[N_PIX][NUM_MAC];

    integer p, j, c;
    longint cycle_count, start_cycle, end_cycle, total_cycles;
    integer pix_captured;
    integer errors;
    longint total_macs;

    top #(
        .NUM_MAC(NUM_MAC), .DATA_WIDTH(DATA_WIDTH), .ACC_WIDTH(ACC_WIDTH)
    ) dut (
        .clk(clk), .rst(rst),
        .s_tvalid(s_tvalid), .s_tready(s_tready),
        .s_first(s_first), .s_last(s_last),
        .s_activation(s_activation), .s_weights(s_weights),
        .m_tvalid(m_tvalid), .m_tready(m_tready), .m_results(m_results)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;   // 100 MHz nominal sim clock
    end

    initial cycle_count = 0;
    always @(posedge clk) cycle_count = cycle_count + 1;

    // Build deterministic signed INT8 stimulus and the golden reference.
    task automatic build_vectors;
        begin
            for (p = 0; p < N_PIX; p = p + 1)
                for (j = 0; j < L; j = j + 1)
                    act_mem[p][j] = (((p*3 + j) % 5) - 2);     // [-2,2]
            for (c = 0; c < NUM_MAC; c = c + 1)
                for (j = 0; j < L; j = j + 1)
                    w_mem[c][j] = (((c + j) % 7) - 3);         // [-3,3]
            for (p = 0; p < N_PIX; p = p + 1)
                for (c = 0; c < NUM_MAC; c = c + 1) begin
                    expected[p][c] = '0;
                    for (j = 0; j < L; j = j + 1)
                        expected[p][c] = expected[p][c] + (act_mem[p][j] * w_mem[c][j]);
                end
        end
    endtask

    // Capture results as output-stream beats are accepted.
    always @(posedge clk) begin
        if (m_tvalid && m_tready && !rst) begin
            for (c = 0; c < NUM_MAC; c = c + 1) begin
                if ($signed(m_results[c*ACC_WIDTH +: ACC_WIDTH]) !== expected[pix_captured][c]) begin
                    errors = errors + 1;
                    if (errors <= 5)
                        $display("MISMATCH pix=%0d ch=%0d got=%0d exp=%0d",
                                 pix_captured, c,
                                 $signed(m_results[c*ACC_WIDTH +: ACC_WIDTH]),
                                 expected[pix_captured][c]);
                end
            end
            pix_captured = pix_captured + 1;
        end
    end

    initial begin
        $dumpfile("project/m4/sim/final_top.vcd");
        $dumpvars(0, clk, rst, s_tvalid, s_tready, s_first, s_last,
                  m_tvalid, m_tready, mon_act, mon_res0,
                  dut.core_in_valid, dut.core_in_first, dut.core_in_last,
                  dut.core_out_valid);

        rst = 1'b1;
        s_tvalid = 1'b0; s_first = 1'b0; s_last = 1'b0;
        s_activation = '0; s_weights = '0;
        m_tready = 1'b1;
        pix_captured = 0; errors = 0;
        build_vectors();

        repeat (3) @(posedge clk);
        @(negedge clk); rst = 1'b0;

        @(negedge clk);
        start_cycle = cycle_count;

        // Stream N_PIX pixels x L elements back-to-back through the input stream.
        for (p = 0; p < N_PIX; p = p + 1) begin
            for (j = 0; j < L; j = j + 1) begin
                s_tvalid = 1'b1;
                s_first  = (j == 0);
                s_last   = (j == L-1);
                s_activation = act_mem[p][j];
                for (c = 0; c < NUM_MAC; c = c + 1)
                    s_weights[c*DATA_WIDTH +: DATA_WIDTH] = w_mem[c][j];
                // Respect backpressure: only advance on an accepted beat.
                @(negedge clk);
                while (!s_tready) @(negedge clk);
            end
        end
        s_tvalid = 1'b0; s_first = 1'b0; s_last = 1'b0;

        // Drain pipeline and capture remaining results.
        while (pix_captured < N_PIX) @(negedge clk);
        end_cycle = cycle_count;

        total_cycles = end_cycle - start_cycle;
        total_macs   = longint'(N_PIX) * longint'(L) * longint'(NUM_MAC);

        $display("M4 TOP END-TO-END BENCH --------------------------------");
        $display("  NUM_MAC=%0d  L=%0d  N_PIX=%0d", NUM_MAC, L, N_PIX);
        $display("  pixels_captured=%0d  errors=%0d", pix_captured, errors);
        $display("  total_macs=%0d", total_macs);
        $display("  stream_cycles=%0d", total_cycles);
        $display("  sustained_macs_per_cycle=%0d.%03d",
                 total_macs / total_cycles,
                 ((total_macs * 1000) / total_cycles) % 1000);
        if (errors == 0)
            $display("PASS: m4 128-MAC array end-to-end");
        else
            $display("FAIL: m4 128-MAC array (%0d mismatches)", errors);
        $finish;
    end
endmodule
