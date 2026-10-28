`timescale 1ns/1ps

module internal_config_ram #(
  parameter int WORD_WIDTH = 32,
  parameter int DEPTH      = 512
)(
  input  logic clk,
  input  logic rst_n,
  input  logic [31:0] wr_addr,
  input  logic [WORD_WIDTH-1:0] wr_data,
  input  logic wr_en,
  input  logic [31:0] rd_addr,
  output logic [WORD_WIDTH-1:0] rd_data
);
  // Purpose: internal BRAM used to store configuration and bitstream descriptors.
  // Inputs: clk, rst_n, wr_addr, wr_data, wr_en, rd_addr
  // Outputs: rd_data
  // Clock/reset: clk, rst_n
  // Assumption: no special ECC or parity is required in the first implementation.

  logic [WORD_WIDTH-1:0] ram [0:DEPTH-1];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rd_data <= '0;
    end else begin
      if (wr_en) ram[wr_addr[31:0]] <= wr_data;
      rd_data <= ram[rd_addr[31:0]];
    end
  end
endmodule
