`timescale 1ns/1ps

module sync_fifo #(
  parameter int DATA_WIDTH = 32,
  parameter int DEPTH      = 16
)(
  input  logic clk,
  input  logic rst_n,
  input  logic [DATA_WIDTH-1:0] wr_data,
  input  logic wr_en,
  output logic [DATA_WIDTH-1:0] rd_data,
  input  logic rd_en,
  output logic full,
  output logic empty,
  output logic almost_full,
  output logic almost_empty,
  output logic [$clog2(DEPTH):0] count
);
  // Purpose: synchronous FIFO used for buffering in data-plane paths.
  // Inputs: clk, rst_n, wr_data, wr_en, rd_en
  // Outputs: rd_data, full, empty, almost_full, almost_empty, count
  // Clock/reset: clk, rst_n
  // Assumption: single clock domain, no backpressure beyond full/empty flags.

  logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];
  logic [$clog2(DEPTH)-1:0] wr_ptr;
  logic [$clog2(DEPTH)-1:0] rd_ptr;
  logic [$clog2(DEPTH):0] count_int;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_ptr <= '0;
      rd_ptr <= '0;
      count_int <= '0;
      full <= 1'b0;
      empty <= 1'b1;
      almost_full <= 1'b0;
      almost_empty <= 1'b1;
      rd_data <= '0;
    end else begin
      if (wr_en && !full) begin
        mem[wr_ptr] <= wr_data;
        wr_ptr <= wr_ptr + 1'b1;
      end

      if (rd_en && !empty) begin
        rd_data <= mem[rd_ptr];
        rd_ptr <= rd_ptr + 1'b1;
      end

      if (wr_en && !full && !(rd_en && !empty)) begin
        count_int <= count_int + 1'b1;
      end else if (rd_en && !empty && !(wr_en && !full)) begin
        count_int <= count_int - 1'b1;
      end

      full <= (count_int >= DEPTH-1);
      empty <= (count_int == '0);
      almost_full <= (count_int >= (DEPTH >> 1));
      almost_empty <= (count_int <= 1);
      count <= count_int;
    end
  end

  // Basic safety checks.
  // synthesis translate_off
  always_ff @(posedge clk) begin
    if (wr_en && full) $error("FIFO write when full");
    if (rd_en && empty) $error("FIFO read when empty");
  end
  // synthesis translate_on
endmodule
