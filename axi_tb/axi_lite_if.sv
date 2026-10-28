`timescale 1ns/1ps

interface axi_lite_if(input logic clk);
  logic rst_n;
  logic [31:0] awaddr;
  logic awvalid, awready;
  logic [31:0] wdata;
  logic [3:0] wstrb;
  logic wvalid, wready;
  logic [1:0] bresp;
  logic bvalid, bready;
  logic [31:0] araddr;
  logic arvalid, arready;
  logic [31:0] rdata;
  logic [1:0] rresp;
  logic rvalid, rready;

  logic [31:0] read_data;
  logic read_valid;
  logic [31:0] write_data;
  logic write_req;
  logic read_req;
  logic [31:0] write_addr;
  logic [31:0] read_addr;
endinterface
