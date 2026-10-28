`timescale 1ns/1ps

module dma_stream_source #(
  parameter int DATA_WIDTH = 32
)(
  input  logic clk,
  input  logic rst_n,
  input  logic start,
  input  logic [31:0] transfer_length,
  input  logic [31:0] src_addr,
  output logic [DATA_WIDTH-1:0] tdata,
  output logic [DATA_WIDTH/8-1:0] tkeep,
  output logic tvalid,
  input  logic tready,
  output logic tlast,
  output logic done,
  output logic error
);
  // Purpose: emit DMA words as AXI4-Stream using a simple register-driven transfer engine.
  // Inputs: clk, rst_n, start, transfer_length, src_addr, tready
  // Outputs: tdata, tkeep, tvalid, tlast, done, error
  // Clock/reset: clk, rst_n
  // Assumption: data is a simple deterministic pattern for testing and protocol validation.

  logic [31:0] count;
  logic active;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      active <= 1'b0; tvalid <= 1'b0; tlast <= 1'b0; count <= '0; done <= 1'b0; error <= 1'b0; tdata <= '0; tkeep <= '1;
    end else begin
      done <= 1'b0;
      if (start && !active) begin
        active <= 1'b1; count <= transfer_length; tvalid <= 1'b1; tlast <= 1'b0; tdata <= src_addr[DATA_WIDTH-1:0] + count;
      end else if (active && tvalid && tready) begin
        count <= count - 1'b1;
        tdata <= tdata + 1'b1;
        if (count == 1) begin
          tlast <= 1'b1;
          tvalid <= 1'b0;
          done <= 1'b1;
          active <= 1'b0;
        end
      end
    end
  end
endmodule
