`timescale 1ns/1ps

/*
 * CF09 Task 7 -- cycle-accurate throughput benchmark for the M3 compute lane.
 *
 * Drives the M2/M3 `compute_core` single 9-tap INT8 MAC lane back-to-back for
 * N_DOTS dot products and counts the total clock cycles from the first START
 * to the last DONE. This yields a *measured* cycles-per-9-tap-dot-product for
 * the synthesized RTL, which is then extrapolated to the full convolution
 * layer in benchmark_results.md.
 *
 * One lane invocation = a 9-tap dot product = 9 MACs = 18 INT8 ops.
 */
module tb_bench;
    localparam int TAPS = 9;
    localparam int DATA_WIDTH = 8;
    localparam int ACC_WIDTH = 32;
    localparam int N_DOTS = 1000;

    logic clk, rst, start;
    logic signed [TAPS*DATA_WIDTH-1:0] activations;
    logic signed [TAPS*DATA_WIDTH-1:0] weights;
    logic signed [ACC_WIDTH-1:0] bias;
    logic busy, done;
    logic signed [ACC_WIDTH-1:0] result;

    integer i;
    integer dots_done;
    longint  start_cycle, end_cycle, cycle_count;
    longint  total_cycles;

    compute_core #(.TAPS(TAPS), .DATA_WIDTH(DATA_WIDTH), .ACC_WIDTH(ACC_WIDTH)) dut (
        .clk(clk), .rst(rst), .start(start),
        .activations(activations), .weights(weights), .bias(bias),
        .busy(busy), .done(done), .result(result)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;   // 100 MHz nominal sim clock (10 ns)
    end

    // free-running cycle counter
    initial cycle_count = 0;
    always @(posedge clk) cycle_count = cycle_count + 1;

    initial begin
        rst = 1'b1;
        start = 1'b0;
        bias = 32'sd0;
        // representative non-trivial tap pattern (signed INT8)
        for (i = 0; i < TAPS; i = i + 1) begin
            activations[i*DATA_WIDTH +: DATA_WIDTH] = (i * 7 - 64);
            weights[i*DATA_WIDTH +: DATA_WIDTH]     = (i * 5 - 32);
        end

        repeat (2) @(posedge clk);
        @(negedge clk); rst = 1'b0;

        dots_done = 0;
        @(negedge clk);
        start_cycle = cycle_count;

        // Issue N_DOTS dot products back-to-back: pulse start whenever idle.
        while (dots_done < N_DOTS) begin
            if (!busy && !start) begin
                start = 1'b1;
                @(negedge clk);
                start = 1'b0;
            end
            @(negedge clk);
            if (done) dots_done = dots_done + 1;
        end
        end_cycle = cycle_count;
        total_cycles = end_cycle - start_cycle;

        $display("BENCH N_DOTS=%0d total_cycles=%0d cycles_per_dot=%0d.%03d",
                 N_DOTS, total_cycles,
                 total_cycles / N_DOTS,
                 ((total_cycles * 1000) / N_DOTS) % 1000);
        $display("BENCH macs_per_dot=9 ops_per_dot=18 last_result=%0d", result);
        $finish;
    end
endmodule
