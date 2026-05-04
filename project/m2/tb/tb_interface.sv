`timescale 1ns/1ps

module tb_interface;
    localparam logic [3:0] OPCODE_WRITE_CONFIG = 4'h1;
    localparam logic [3:0] OPCODE_READ_CONFIG  = 4'h2;
    localparam logic [3:0] OPCODE_RESPONSE     = 4'hA;
    localparam logic [27:0] TEST_CONFIG        = 28'h00ABCD1;

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
    logic [27:0] config_reg;

    axis_interface dut (
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
        .config_reg(config_reg)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        $dumpfile("project/m2/sim/interface.vcd");
        $dumpvars(0, tb_interface);

        rst = 1'b1;
        s_axis_tdata = 32'd0;
        s_axis_tvalid = 1'b0;
        s_axis_tlast = 1'b0;
        m_axis_tready = 1'b0;

        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        @(posedge clk);
        #1;

        if (!s_axis_tready) begin
            $display("FAIL: interface not ready for write transaction");
            $finish;
        end

        @(negedge clk);
        s_axis_tdata = {OPCODE_WRITE_CONFIG, TEST_CONFIG};
        s_axis_tlast = 1'b1;
        s_axis_tvalid = 1'b1;
        @(posedge clk);
        #1;
        if (!s_axis_tready) begin
            $display("FAIL: write transaction did not see ready asserted");
            $finish;
        end

        @(negedge clk);
        s_axis_tvalid = 1'b0;
        s_axis_tlast = 1'b0;
        s_axis_tdata = 32'd0;
        @(posedge clk);
        #1;
        if (config_reg !== TEST_CONFIG) begin
            $display("FAIL: config register mismatch config=%h expected=%h", config_reg, TEST_CONFIG);
            $finish;
        end
        $display("Write transaction stored config=%h", config_reg);

        if (!s_axis_tready) begin
            $display("FAIL: interface not ready for read transaction");
            $finish;
        end

        @(negedge clk);
        s_axis_tdata = {OPCODE_READ_CONFIG, 28'd0};
        s_axis_tlast = 1'b1;
        s_axis_tvalid = 1'b1;
        @(posedge clk);
        #1;

        @(negedge clk);
        s_axis_tvalid = 1'b0;
        s_axis_tlast = 1'b0;
        s_axis_tdata = 32'd0;
        @(posedge clk);
        #1;
        if (!m_axis_tvalid || !m_axis_tlast || m_axis_tdata !== {OPCODE_RESPONSE, TEST_CONFIG}) begin
            $display("FAIL: response mismatch valid=%b last=%b data=%h expected=%h",
                     m_axis_tvalid, m_axis_tlast, m_axis_tdata, {OPCODE_RESPONSE, TEST_CONFIG});
            $finish;
        end

        @(negedge clk);
        m_axis_tready = 1'b1;
        @(posedge clk);
        #1;
        if (m_axis_tvalid) begin
            $display("FAIL: response valid remained high after ready handshake");
            $finish;
        end
        $display("Read response returned data=%h", {OPCODE_RESPONSE, TEST_CONFIG});

        $display("PASS: interface");
        $finish;
    end
endmodule
