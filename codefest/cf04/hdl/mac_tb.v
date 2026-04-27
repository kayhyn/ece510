`timescale 1ns/1ps

module mac_tb;
    logic clk;
    logic rst;
    logic signed [7:0] a;
    logic signed [7:0] b;
    logic signed [31:0] out;

    mac dut (
        .clk(clk),
        .rst(rst),
        .a(a),
        .b(b),
        .out(out)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic check_output(input string label, input logic signed [31:0] expected);
        begin
            #1;
            $display("%s: out=%0d expected=%0d", label, out, expected);
            if (out !== expected) begin
                $error("%s failed: out=%0d expected=%0d", label, out, expected);
                $finish;
            end
        end
    endtask

    initial begin
        rst = 1'b1;
        a = 8'sd0;
        b = 8'sd0;

        @(posedge clk);
        check_output("reset", 32'sd0);

        rst = 1'b0;
        a = 8'sd3;
        b = 8'sd4;

        @(posedge clk);
        check_output("3*4 cycle 1", 32'sd12);
        @(posedge clk);
        check_output("3*4 cycle 2", 32'sd24);
        @(posedge clk);
        check_output("3*4 cycle 3", 32'sd36);

        rst = 1'b1;
        @(posedge clk);
        check_output("reset between sequences", 32'sd0);

        rst = 1'b0;
        a = -8'sd5;
        b = 8'sd2;

        @(posedge clk);
        check_output("-5*2 cycle 1", -32'sd10);
        @(posedge clk);
        check_output("-5*2 cycle 2", -32'sd20);

        $display("PASS");
        $finish;
    end
endmodule
