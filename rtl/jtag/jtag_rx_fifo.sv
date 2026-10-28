`timescale 1ns/1ps

module jtag_rx_fifo #(
  parameter int DATA_WIDTH = 32,
  parameter int DEPTH = 16
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
  // Purpose: JTAG RX FIFO for JTAG responses.
  // Inputs: clk, rst_n, wr_data, wr_en, rd_en
  // Outputs: rd_data, full, empty, almost_full, almost_empty, count
  // Clock/reset: clk, rst_n
  // Assumption: single clock domain and reused as the general-purpose synchronous FIFO.

  sync_fifo #(.DATA_WIDTH(DATA_WIDTH), .DEPTH(DEPTH)) u_fifo (
    .clk(clk),
    .rst_n(rst_n),
    .wr_data(wr_data),
    .wr_en(wr_en),
    .rd_data(rd_data),
    .rd_en(rd_en),
    .full(full),
    .empty(empty),
    .almost_full(almost_full),
    .almost_empty(almost_empty),
    .count(count)
  );
endmodule
