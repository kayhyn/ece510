`timescale 1ns/1ps

/*
 * Testbench: tb_mac_array
 *
 * Cycle-accurate verification + throughput measurement for the M4 128-MAC array.
 *
 * Workload: a representative slice of the dominant 3x3 INT8 convolution. The TB
 * streams N_PIX output pixels; each pixel reduces over L = Kh*Kw*Cin = 576
 * elements (the full 3x3x64 window). The 128 lanes compute 128 output channels
 * in parallel. Activations are shared across channels (as in convolution);
 * weights are reused unchanged across all pixels (weight reuse). Data are
 * streamed back-to-back with no bubbles so the measured cycle count reflects
 * sustained steady-state throughput.
 *
 * Checks: an independent SV reference recomputes every pixel/channel result and
 * compares against the array outputs. Reports total cycles for the streamed
 * region and the sustained MACs/cycle, which CF09 extrapolates to the full
 * 2704-pixel layer at the synthesized clock.
 */
module tb_mac_array;
    localparam int NUM_MAC    = 128;
    localparam int DATA_WIDTH = 8;
    localparam int ACC_WIDTH  = 32;
    localparam int L          = 576;   // Kh*Kw*Cin reduction length per pixel
    localparam int N_PIX      = 8;     // representative number of output pixels

    logic clk, rst;
    logic in_valid, in_first, in_last;
    logic signed [DATA_WIDTH-1:0]        activation;
    logic        [NUM_MAC*DATA_WIDTH-1:0] weights;
    logic                                out_valid;
    logic        [NUM_MAC*ACC_WIDTH-1:0]  results;

    // Stimulus storage
    logic signed [DATA_WIDTH-1:0] act_mem [N_PIX][L];   // per-pixel activations
    logic signed [DATA_WIDTH-1:0] w_mem   [NUM_MAC][L]; // per-channel weights (reused)
    logic signed [ACC_WIDTH-1:0]  expected[N_PIX][NUM_MAC];

    integer p, j, c;
    longint cycle_count, start_cycle, end_cycle, total_cycles;
    integer pix_captured;
    integer errors;
    longint total_macs;

    mac_array #(
        .NUM_MAC(NUM_MAC), .DATA_WIDTH(DATA_WIDTH), .ACC_WIDTH(ACC_WIDTH)
    ) dut (
        .clk(clk), .rst(rst),
        .in_valid(in_valid), .in_first(in_first), .in_last(in_last),
        .activation(activation), .weights(weights),
        .out_valid(out_valid), .results(results)
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

    // Capture results as out_valid pulses arrive.
    always @(posedge clk) begin
        if (out_valid && !rst) begin
            for (c = 0; c < NUM_MAC; c = c + 1) begin
                if ($signed(results[c*ACC_WIDTH +: ACC_WIDTH]) !== expected[pix_captured][c]) begin
                    errors = errors + 1;
                    if (errors <= 5)
                        $display("MISMATCH pix=%0d ch=%0d got=%0d exp=%0d",
                                 pix_captured, c,
                                 $signed(results[c*ACC_WIDTH +: ACC_WIDTH]),
                                 expected[pix_captured][c]);
                end
            end
            pix_captured = pix_captured + 1;
        end
    end

    initial begin
        $dumpfile("project/m4/sim/mac_array.vcd");
        $dumpvars(1, tb_mac_array);

        rst = 1'b1;
        in_valid = 1'b0; in_first = 1'b0; in_last = 1'b0;
        activation = '0; weights = '0;
        pix_captured = 0; errors = 0;
        build_vectors();

        repeat (3) @(posedge clk);
        @(negedge clk); rst = 1'b0;

        @(negedge clk);
        start_cycle = cycle_count;

        // Stream N_PIX pixels x L elements back-to-back.
        for (p = 0; p < N_PIX; p = p + 1) begin
            for (j = 0; j < L; j = j + 1) begin
                in_valid = 1'b1;
                in_first = (j == 0);
                in_last  = (j == L-1);
                activation = act_mem[p][j];
                for (c = 0; c < NUM_MAC; c = c + 1)
                    weights[c*DATA_WIDTH +: DATA_WIDTH] = w_mem[c][j];
                @(negedge clk);
            end
        end
        in_valid = 1'b0; in_first = 1'b0; in_last = 1'b0;

        // Drain pipeline and capture remaining results.
        while (pix_captured < N_PIX) @(negedge clk);
        end_cycle = cycle_count;

        total_cycles = end_cycle - start_cycle;
        total_macs   = longint'(N_PIX) * longint'(L) * longint'(NUM_MAC);

        $display("M4 MAC-ARRAY BENCH ------------------------------------");
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
