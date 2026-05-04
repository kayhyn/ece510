`timescale 1ns/1ps

module tb_compute_core;
    localparam int TAPS = 9;
    localparam int DATA_WIDTH = 8;
    localparam int ACC_WIDTH = 32;

    logic clk;
    logic rst;
    logic start;
    logic signed [TAPS*DATA_WIDTH-1:0] activations;
    logic signed [TAPS*DATA_WIDTH-1:0] weights;
    logic signed [ACC_WIDTH-1:0] bias;
    logic busy;
    logic done;
    logic signed [ACC_WIDTH-1:0] result;

    logic signed [7:0] activation_ref [0:TAPS-1];
    logic signed [7:0] weight_ref [0:TAPS-1];
    logic signed [31:0] expected;
    int i;
    int timeout;

    compute_core #(
        .TAPS(TAPS),
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .activations(activations),
        .weights(weights),
        .bias(bias),
        .busy(busy),
        .done(done),
        .result(result)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic load_reference_vectors;
        begin
            activation_ref[0] = 8'sd3;
            activation_ref[1] = -8'sd2;
            activation_ref[2] = 8'sd7;
            activation_ref[3] = 8'sd0;
            activation_ref[4] = 8'sd5;
            activation_ref[5] = -8'sd4;
            activation_ref[6] = 8'sd9;
            activation_ref[7] = 8'sd1;
            activation_ref[8] = -8'sd8;

            weight_ref[0] = 8'sd2;
            weight_ref[1] = 8'sd6;
            weight_ref[2] = -8'sd3;
            weight_ref[3] = 8'sd4;
            weight_ref[4] = -8'sd1;
            weight_ref[5] = 8'sd5;
            weight_ref[6] = 8'sd0;
            weight_ref[7] = -8'sd7;
            weight_ref[8] = 8'sd8;
        end
    endtask

    task automatic pack_vectors;
        begin
            activations = '0;
            weights = '0;
            for (i = 0; i < TAPS; i = i + 1) begin
                activations[i*DATA_WIDTH +: DATA_WIDTH] = activation_ref[i];
                weights[i*DATA_WIDTH +: DATA_WIDTH] = weight_ref[i];
            end
        end
    endtask

    task automatic compute_expected;
        begin
            expected = bias;
            for (i = 0; i < TAPS; i = i + 1) begin
                expected = expected + (activation_ref[i] * weight_ref[i]);
            end
        end
    endtask

    initial begin
        $dumpfile("project/m2/sim/compute_core.vcd");
        $dumpvars(0, tb_compute_core);

        rst = 1'b1;
        start = 1'b0;
        bias = 32'sd13;
        load_reference_vectors();
        pack_vectors();
        compute_expected();

        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        @(negedge clk);
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;

        timeout = 0;
        while (!done && timeout < 20) begin
            @(posedge clk);
            #1;
            timeout = timeout + 1;
        end

        $display("Representative 3x3 INT8 dot product expected=%0d result=%0d", expected, result);
        if (!done) begin
            $display("FAIL: compute_core did not assert done before timeout");
            $finish;
        end

        if (result !== expected) begin
            $display("FAIL: compute_core result mismatch");
            $finish;
        end

        $display("PASS: compute_core");
        $finish;
    end
endmodule
