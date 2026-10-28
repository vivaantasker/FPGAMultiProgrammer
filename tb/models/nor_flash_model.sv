`timescale 1ns/1ps

module nor_flash_model #(
  parameter int ADDR_WIDTH = 24,
  parameter int DATA_WIDTH = 32,
  parameter int DEPTH = 4096
)(
  input  logic clk,
  input  logic rst_n,
  input  logic cs_n,
  input  logic sclk,
  input  logic mosi,
  output logic miso,
  input  logic [ADDR_WIDTH-1:0] addr,
  input  logic [15:0] length,
  input  logic read_req,
  output logic busy,
  output logic done,
  output logic error
);
  // Purpose: simple model of a preloaded NOR flash.
  // Inputs: clk, rst_n, cs_n, sclk, mosi, addr, length, read_req
  // Outputs: miso, busy, done, error
  // Clock/reset: clk, rst_n
  // Assumption: model is simple and stores a deterministic bitstream pattern.

  logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];
  logic [15:0] count;
  logic [ADDR_WIDTH-1:0] addr_q;

  initial begin
    for (int i = 0; i < DEPTH; i++) mem[i] = 32'h0000_0000 + i;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      busy <= 1'b0; done <= 1'b0; error <= 1'b0; miso <= 1'b0; count <= '0; addr_q <= '0;
    end else begin
      if (read_req && !cs_n) begin
        busy <= 1'b1; addr_q <= addr; count <= length;
      end
      if (busy) begin
        if (count > 0) begin
          miso <= mem[addr_q][count[1:0]];
          count <= count - 1'b1;
        end else begin
          busy <= 1'b0; done <= 1'b1; miso <= 1'b0;
        end
      end
    end
  end
endmodule
