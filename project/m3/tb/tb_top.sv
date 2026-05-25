`timescale 1ns/1ps

module tb_top;
    localparam int TAPS = 9;
    localparam int DATA_WIDTH = 8;

    localparam logic [3:0] OPCODE_WRITE_CONFIG = 4'h1;
    localparam logic [3:0] RESP_RESULT         = 4'hB;

    localparam logic [3:0] CMD_LOAD_ACTIVATION = 4'h0;
    localparam logic [3:0] CMD_LOAD_WEIGHT     = 4'h1;
    localparam logic [3:0] CMD_LOAD_BIAS_LO    = 4'h2;
    localparam logic [3:0] CMD_LOAD_BIAS_HI    = 4'h3;
    localparam logic [3:0] CMD_START           = 4'h4;
    localparam logic [3:0] CMD_READ_RESULT     = 4'h5;

    logic clk;
    logic rst;
    logic [31:0] s_axis_tdata;
    logic s_axis_tvalid;
    logic s_axis_tready;
    logic s_axis_tlast;
    logic [31:0] m_axis_tdata;
    logic m_axis_tvalid;
    logic m_axis_tready;
    logic m_axis_tlast;
    logic compute_busy;
    logic compute_done;

    logic signed [7:0] activation_ref [0:TAPS-1];
    logic signed [7:0] weight_ref [0:TAPS-1];
    logic signed [31:0] bias_ref;
    logic signed [31:0] expected;
    logic signed [31:0] observed;
    logic [31:0] response_word;
    int i;
    int timeout;

    top dut (
        .clk(clk),
        .rst(rst),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast(s_axis_tlast),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(m_axis_tlast),
        .compute_busy(compute_busy),
        .compute_done(compute_done)
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

    task automatic compute_expected;
        begin
            expected = bias_ref;
            for (i = 0; i < TAPS; i = i + 1) begin
                expected = expected + (activation_ref[i] * weight_ref[i]);
            end
        end
    endtask

    task automatic host_write(input logic [3:0] subcommand,
                              input logic [3:0] tap,
                              input logic [15:0] payload);
        begin
            @(negedge clk);
            s_axis_tdata = {OPCODE_WRITE_CONFIG, subcommand, tap, 4'd0, payload};
            s_axis_tlast = 1'b1;
            s_axis_tvalid = 1'b1;

            do begin
                @(posedge clk);
                #1;
            end while (!s_axis_tready);

            @(negedge clk);
            s_axis_tvalid = 1'b0;
            s_axis_tlast = 1'b0;
            s_axis_tdata = 32'd0;
        end
    endtask

    initial begin
        $dumpfile("project/m3/sim/top.vcd");
        $dumpvars(0, tb_top);

        rst = 1'b1;
        s_axis_tdata = 32'd0;
        s_axis_tvalid = 1'b0;
        s_axis_tlast = 1'b0;
        m_axis_tready = 1'b0;
        bias_ref = 32'sd13;
        load_reference_vectors();
        compute_expected();

        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        for (i = 0; i < TAPS; i = i + 1) begin
            host_write(CMD_LOAD_ACTIVATION, i[3:0], {8'd0, activation_ref[i]});
        end

        for (i = 0; i < TAPS; i = i + 1) begin
            host_write(CMD_LOAD_WEIGHT, i[3:0], {8'd0, weight_ref[i]});
        end

        host_write(CMD_LOAD_BIAS_LO, 4'd0, bias_ref[15:0]);
        host_write(CMD_LOAD_BIAS_HI, 4'd0, bias_ref[31:16]);
        host_write(CMD_START, 4'd0, 16'd0);

        timeout = 0;
        while (!compute_done && timeout < 30) begin
            @(posedge clk);
            #1;
            timeout = timeout + 1;
        end

        if (!compute_done) begin
            $display("FAIL: integrated top did not assert compute_done before timeout");
            $finish;
        end

        @(posedge clk);
        #1;
        host_write(CMD_READ_RESULT, 4'd0, 16'd0);

        timeout = 0;
        while (!m_axis_tvalid && timeout < 10) begin
            @(posedge clk);
            #1;
            timeout = timeout + 1;
        end

        if (!m_axis_tvalid || !m_axis_tlast || m_axis_tdata[31:28] !== RESP_RESULT) begin
            $display("FAIL: result response invalid valid=%b last=%b data=%h",
                     m_axis_tvalid, m_axis_tlast, m_axis_tdata);
            $finish;
        end

        observed = {{4{m_axis_tdata[27]}}, m_axis_tdata[27:0]};
        response_word = m_axis_tdata;
        m_axis_tready = 1'b1;
        @(posedge clk);
        #1;
        m_axis_tready = 1'b0;

        $display("Host programmed 9 activation taps, 9 weight taps, and bias over AXI4-Stream");
        $display("Representative 3x3 INT8 dot product expected=%0d observed=%0d response=%h",
                 expected, observed, response_word);

        if (observed !== expected) begin
            $display("FAIL: integrated top result mismatch");
            $finish;
        end

        $display("PASS: m3 end-to-end cosim");
        $finish;
    end
endmodule
