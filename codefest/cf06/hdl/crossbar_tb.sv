`timescale 1ns/1ps

// Testbench for the 4x4 binary-weight crossbar MAC.
//
// Loads the weight matrix
//
//     W = [[ 1, -1,  1, -1],
//          [ 1,  1, -1, -1],
//          [-1,  1,  1, -1],
//          [-1, -1, -1,  1]]
//
// applies the input vector x = [10, 20, 30, 40], and confirms that the
// crossbar produces the hand-calculated output vector
//
//     out[j] = sum_i W[i][j] * x[i]  =  [-40, 0, -20, -20]

module crossbar_tb;

    localparam int N         = 4;
    localparam int IN_WIDTH  = 8;
    localparam int ACC_WIDTH = 16;

    logic                          clk;
    logic                          rst;
    logic                          load_w;
    logic [N*N-1:0]                weight_in;
    logic signed [IN_WIDTH-1:0]    in_vec    [N];
    logic signed [ACC_WIDTH-1:0]   out_vec   [N];

    crossbar_mac #(
        .N         (N),
        .IN_WIDTH  (IN_WIDTH),
        .ACC_WIDTH (ACC_WIDTH)
    ) dut (
        .clk       (clk),
        .rst       (rst),
        .load_w    (load_w),
        .weight_in (weight_in),
        .in_vec    (in_vec),
        .out_vec   (out_vec)
    );

    // 100 MHz clock
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // Helper: write a +1/-1 row into the 1-bit-per-cell weight vector
    // using the encoding 0 -> +1, 1 -> -1.  Cell (row, col) lives at
    // bit row*N + col so that it matches the DUT's flattening.
    task automatic load_row(input int row,
                            input int signed v0,
                            input int signed v1,
                            input int signed v2,
                            input int signed v3);
        weight_in[row*N + 0] = (v0 == -1);
        weight_in[row*N + 1] = (v1 == -1);
        weight_in[row*N + 2] = (v2 == -1);
        weight_in[row*N + 3] = (v3 == -1);
    endtask

    task automatic check_outputs(
        input string                       label,
        input logic signed [ACC_WIDTH-1:0] e0,
        input logic signed [ACC_WIDTH-1:0] e1,
        input logic signed [ACC_WIDTH-1:0] e2,
        input logic signed [ACC_WIDTH-1:0] e3
    );
        begin
            #1;
            $display("%s: out=[%0d, %0d, %0d, %0d] expected=[%0d, %0d, %0d, %0d]",
                     label,
                     out_vec[0], out_vec[1], out_vec[2], out_vec[3],
                     e0, e1, e2, e3);
            if (out_vec[0] !== e0 || out_vec[1] !== e1 ||
                out_vec[2] !== e2 || out_vec[3] !== e3) begin
                $error("%s mismatch", label);
                $finish;
            end
        end
    endtask

    function automatic logic signed [ACC_WIDTH-1:0] expected_col(
        input int col,
        input logic signed [IN_WIDTH-1:0] v0,
        input logic signed [IN_WIDTH-1:0] v1,
        input logic signed [IN_WIDTH-1:0] v2,
        input logic signed [IN_WIDTH-1:0] v3
    );
        int signed acc;
        begin
            acc = 0;
            acc = acc + (weight_in[0*N + col] ? -v0 : v0);
            acc = acc + (weight_in[1*N + col] ? -v1 : v1);
            acc = acc + (weight_in[2*N + col] ? -v2 : v2);
            acc = acc + (weight_in[3*N + col] ? -v3 : v3);
            expected_col = acc;
        end
    endfunction

    task automatic load_flat_weights(input logic [N*N-1:0] bits);
        begin
            #1;
            weight_in = bits;
            load_w = 1'b1;
            @(posedge clk);
            #1;
            load_w = 1'b0;
        end
    endtask

    task automatic apply_and_check(
        input string label,
        input logic signed [IN_WIDTH-1:0] v0,
        input logic signed [IN_WIDTH-1:0] v1,
        input logic signed [IN_WIDTH-1:0] v2,
        input logic signed [IN_WIDTH-1:0] v3
    );
        begin
            #1;
            in_vec[0] = v0;
            in_vec[1] = v1;
            in_vec[2] = v2;
            in_vec[3] = v3;

            @(posedge clk);
            check_outputs(label,
                          expected_col(0, v0, v1, v2, v3),
                          expected_col(1, v0, v1, v2, v3),
                          expected_col(2, v0, v1, v2, v3),
                          expected_col(3, v0, v1, v2, v3));
        end
    endtask

    initial begin
        int seed;
        int k;
        logic signed [IN_WIDTH-1:0] r0;
        logic signed [IN_WIDTH-1:0] r1;
        logic signed [IN_WIDTH-1:0] r2;
        logic signed [IN_WIDTH-1:0] r3;

        // --- Phase 0: hold reset ---
        rst       = 1'b1;
        load_w    = 1'b0;
        weight_in = '0;
        in_vec[0] = 8'sd0;
        in_vec[1] = 8'sd0;
        in_vec[2] = 8'sd0;
        in_vec[3] = 8'sd0;

        @(posedge clk);
        check_outputs("reset", 16'sd0, 16'sd0, 16'sd0, 16'sd0);

        // --- Phase 1: load weight matrix ---
        // W row i goes into weight_in[i].
        rst    = 1'b0;
        load_w = 1'b1;
        load_row(0,  1, -1,  1, -1);
        load_row(1,  1,  1, -1, -1);
        load_row(2, -1,  1,  1, -1);
        load_row(3, -1, -1, -1,  1);

        @(posedge clk);   // weight register now holds W
        #1;               // step off the edge to avoid sample races

        // --- Phase 2: apply input vector and let it propagate ---
        load_w    = 1'b0;
        in_vec[0] = 8'sd10;
        in_vec[1] = 8'sd20;
        in_vec[2] = 8'sd30;
        in_vec[3] = 8'sd40;

        @(posedge clk);   // out_vec now registers W * x

        // Hand calculation:
        //   out[0] =  1*10 +  1*20 + -1*30 + -1*40 = -40
        //   out[1] = -1*10 +  1*20 +  1*30 + -1*40 =   0
        //   out[2] =  1*10 + -1*20 +  1*30 + -1*40 = -20
        //   out[3] = -1*10 + -1*20 + -1*30 +  1*40 = -20
        check_outputs("W*x [10,20,30,40]",
                      -16'sd40, 16'sd0, -16'sd20, -16'sd20);

        // --- Phase 3: try a second input vector with same weights ---
        // x' = [1, 2, 3, 4]
        //   out[0] =  1+ 2- 3- 4 = -4
        //   out[1] = -1+ 2+ 3- 4 =  0
        //   out[2] =  1- 2+ 3- 4 = -2
        //   out[3] = -1- 2- 3+ 4 = -2
        #1;
        in_vec[0] = 8'sd1;
        in_vec[1] = 8'sd2;
        in_vec[2] = 8'sd3;
        in_vec[3] = 8'sd4;

        @(posedge clk);
        check_outputs("W*x' [1,2,3,4]",
                      -16'sd4, 16'sd0, -16'sd2, -16'sd2);

        // --- Phase 4: negative input also works ---
        // x'' = [-8, 16, -32, 64]
        //   out[0] =  1*-8 +  1*16 + -1*-32 + -1*64 = -8+16+32-64 = -24
        //   out[1] = -1*-8 +  1*16 +  1*-32 + -1*64 =  8+16-32-64 = -72
        //   out[2] =  1*-8 + -1*16 +  1*-32 + -1*64 = -8-16-32-64 = -120
        //   out[3] = -1*-8 + -1*16 + -1*-32 +  1*64 =  8-16+32+64 =  88
        #1;
        in_vec[0] = -8'sd8;
        in_vec[1] =  8'sd16;
        in_vec[2] = -8'sd32;
        in_vec[3] =  8'sd64;

        @(posedge clk);
        check_outputs("W*x'' [-8,16,-32,64]",
                      -16'sd24, -16'sd72, -16'sd120, 16'sd88);

        // --- Phase 5: edge cases and randomized checks ---
        load_flat_weights('0);
        apply_and_check("edge all + weights [127,127,127,127]",
                        8'sh7f, 8'sh7f, 8'sh7f, 8'sh7f);

        load_flat_weights('1);
        apply_and_check("edge all - weights [-128,-128,-128,-128]",
                        8'sh80, 8'sh80, 8'sh80, 8'sh80);

        seed = 32'h5100_0006;
        for (k = 0; k < 10; k++) begin
            load_flat_weights($random(seed));
            r0 = $random(seed);
            r1 = $random(seed);
            r2 = $random(seed);
            r3 = $random(seed);
            apply_and_check($sformatf("random %0d", k), r0, r1, r2, r3);
        end

        // --- Phase 6: reset clears outputs ---
        #1;
        rst = 1'b1;
        @(posedge clk);
        check_outputs("reset clears", 16'sd0, 16'sd0, 16'sd0, 16'sd0);

        $display("PASS");
        $finish;
    end

endmodule
