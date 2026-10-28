`timescale 1ns/1ps

module async_fifo #(
  parameter int DATA_WIDTH = 32,
  parameter int DEPTH      = 16
)(
  input  logic wr_clk,
  input  logic rd_clk,
  input  logic rst_n,
  input  logic [DATA_WIDTH-1:0] wr_data,
  input  logic wr_en,
  input  logic rd_en,
  output logic [DATA_WIDTH-1:0] rd_data,
  output logic full,
  output logic empty,
  output logic almost_full,
  output logic almost_empty,
  output logic [$clog2(DEPTH):0] count
);
  // Purpose: cross-clock FIFO with simple pointer-based logic.
  // Inputs: wr_clk, rd_clk, rst_n, wr_data, wr_en, rd_en
  // Outputs: rd_data, full, empty, almost_full, almost_empty, count
  // Clock/reset: separate write/read clock domains with synchronous reset in each domain.
  // Assumption: a full implementation can be added later; this is a synthesizable stub.

  logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];
  logic [$clog2(DEPTH)-1:0] wr_ptr;
  logic [$clog2(DEPTH)-1:0] rd_ptr;
  logic [$clog2(DEPTH):0] count_int;

  always_ff @(posedge wr_clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_ptr <= '0;
      count_int <= '0;
      full <= 1'b0;
    end else if (wr_en && !full) begin
      mem[wr_ptr] <= wr_data;
      wr_ptr <= wr_ptr + 1'b1;
      if (!rd_en) count_int <= count_int + 1'b1;
    end
  end

  always_ff @(posedge rd_clk or negedge rst_n) begin
    if (!rst_n) begin
      rd_ptr <= '0;
      rd_data <= '0;
      empty <= 1'b1;
      almost_empty <= 1'b1;
    end else if (rd_en && !empty) begin
      rd_data <= mem[rd_ptr];
      rd_ptr <= rd_ptr + 1'b1;
      if (!wr_en) count_int <= count_int - 1'b1;
    end
    empty <= (count_int == '0);
    full <= (count_int >= DEPTH-1);
    almost_full <= (count_int >= (DEPTH >> 1));
    almost_empty <= (count_int <= 1);
    count <= count_int;
  end
endmodule
