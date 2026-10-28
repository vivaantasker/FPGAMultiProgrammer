`timescale 1ns/1ps

module dma_regs #(
  parameter int ADDR_WIDTH = 32,
  parameter int DATA_WIDTH = 32
)(
  input  logic clk,
  input  logic rst_n,
  input  logic [ADDR_WIDTH-1:0] awaddr,
  input  logic awvalid,
  output logic awready,
  input  logic [DATA_WIDTH-1:0] wdata,
  input  logic [DATA_WIDTH/8-1:0] wstrb,
  input  logic wvalid,
  output logic wready,
  output logic [1:0] bresp,
  output logic bvalid,
  input  logic bready,
  input  logic [ADDR_WIDTH-1:0] araddr,
  input  logic arvalid,
  output logic arready,
  output logic [DATA_WIDTH-1:0] rdata,
  output logic [1:0] rresp,
  output logic rvalid,
  input  logic rready,
  output logic [ADDR_WIDTH-1:0] source_address,
  output logic [DATA_WIDTH-1:0] transfer_length,
  output logic start,
  output logic abort,
  input  logic done,
  input  logic error,
  input  logic [DATA_WIDTH-1:0] status
);
  // Purpose: DMA configuration registers and status.
  // Inputs: clk, rst_n, axi_if, done, error, status
  // Outputs: source_address, transfer_length, start, abort
  // Clock/reset: clk, rst_n
  // Assumption: no burst operation; register-driven DMA control.

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      source_address <= '0;
      transfer_length <= '0;
      start <= 1'b0;
      abort <= 1'b0;
    end else begin
      if (awvalid && awready) begin
        if (awaddr == 32'h00) source_address <= wdata;
        if (awaddr == 32'h04) transfer_length <= wdata;
      end
      if (wvalid && wready) begin
        if (awaddr == 32'h08) start <= wdata[0];
        if (awaddr == 32'h0C) abort <= wdata[0];
      end
      if (done || error) begin
        start <= 1'b0;
      end
    end
  end

  always_comb begin
    awready = 1'b1;
    wready = 1'b1;
    bvalid = awvalid && wvalid;
    bresp = 2'b00;
    arready = 1'b1;
    rvalid = arvalid;
    rresp = 2'b00;
    rdata = status;
  end
endmodule
