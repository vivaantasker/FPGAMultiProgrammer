`timescale 1ns/1ps

interface axi_stream_if #(parameter int DATA_WIDTH = 32);
  logic [DATA_WIDTH-1:0] tdata;
  logic [DATA_WIDTH/8-1:0] tkeep;
  logic tvalid;
  logic tready;
  logic tlast;

  modport master (
    output tdata, tkeep, tvalid, tlast,
    input  tready
  );

  modport slave (
    input  tdata, tkeep, tvalid, tlast,
    output tready
  );
endinterface
