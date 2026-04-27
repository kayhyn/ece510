`timescale 1ns/1ps

module mac (
    input  logic               clk,
    input  logic               rst,
    input  logic signed [7:0]  a,
    input  logic signed [7:0]  b,
    output logic signed [31:0] out
);

    logic signed [15:0] product;
    logic signed [31:0] product_ext;

    assign product = a * b;
    assign product_ext = {{16{product[15]}}, product};

    always_ff @(posedge clk) begin
        if (rst) begin
            out <= 32'sd0;
        end else begin
            out <= out + product_ext;
        end
    end

endmodule
