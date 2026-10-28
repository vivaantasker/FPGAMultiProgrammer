`timescale 1ns/1ps

module dma_controller #(
  parameter int DATA_WIDTH = 32
)(
  input  logic clk,
  input  logic rst_n,
  input  logic start,
  input  logic abort,
  input  logic [31:0] source_address,
  input  logic [31:0] transfer_length,
  output logic [DATA_WIDTH-1:0] m_axis_tdata,
  output logic [DATA_WIDTH/8-1:0] m_axis_tkeep,
  output logic m_axis_tvalid,
  input  logic m_axis_tready,
  output logic m_axis_tlast,
  output logic done,
  output logic error,
  output logic busy
);
  // Purpose: memory-to-stream DMA controller.
  // Inputs: clk, rst_n, start, abort, source_address, transfer_length, m_axis_tready
  // Outputs: m_axis_tdata, m_axis_tkeep, m_axis_tvalid, m_axis_tlast, done, error, busy
  // Clock/reset: clk, rst_n
  // Assumption: transfer length is a word count and no scatter-gather support yet.

  logic [31:0] count;
  logic active;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      count <= '0; active <= 1'b0; busy <= 1'b0; done <= 1'b0; error <= 1'b0;
      m_axis_tdata <= '0; m_axis_tkeep <= '1; m_axis_tvalid <= 1'b0; m_axis_tlast <= 1'b0;
    end else begin
      done <= 1'b0;
      if (abort) begin
        active <= 1'b0; busy <= 1'b0; m_axis_tvalid <= 1'b0; m_axis_tlast <= 1'b0; error <= 1'b1;
      end else if (start && !active) begin
        active <= 1'b1; busy <= 1'b1; count <= transfer_length; m_axis_tvalid <= 1'b1; m_axis_tlast <= 1'b0; m_axis_tdata <= source_address[DATA_WIDTH-1:0];
      end else if (active && m_axis_tvalid && m_axis_tready) begin
        count <= count - 1'b1;
        m_axis_tdata <= m_axis_tdata + 1'b1;
        if (count == 1) begin
          m_axis_tlast <= 1'b1;
          m_axis_tvalid <= 1'b0;
          busy <= 1'b0; done <= 1'b1; active <= 1'b0;
        end
      end
    end
  end
endmodule
