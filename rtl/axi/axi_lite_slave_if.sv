`timescale 1ns/1ps

interface axi_lite_slave_if #(parameter int ADDR_WIDTH = 32, parameter int DATA_WIDTH = 32);
  logic [ADDR_WIDTH-1:0] awaddr;
  logic awvalid;
  logic awready;
  logic [DATA_WIDTH-1:0] wdata;
  logic [DATA_WIDTH/8-1:0] wstrb;
  logic wvalid;
  logic wready;
  logic [1:0] bresp;
  logic bvalid;
  logic bready;
  logic [ADDR_WIDTH-1:0] araddr;
  logic arvalid;
  logic arready;
  logic [DATA_WIDTH-1:0] rdata;
  logic [1:0] rresp;
  logic rvalid;
  logic rready;

  modport master (
    output awaddr, awvalid, wdata, wstrb, wvalid, bready, araddr, arvalid, rready,
    input  awready, wready, bvalid, bresp, arready, rvalid, rdata, rresp
  );

  modport slave (
    input  awaddr, awvalid, wdata, wstrb, wvalid, bready, araddr, arvalid, rready,
    output awready, wready, bvalid, bresp, arready, rvalid, rdata, rresp
  );
endinterface
