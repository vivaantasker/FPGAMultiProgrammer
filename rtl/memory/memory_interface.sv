`timescale 1ns/1ps

interface memory_interface #(
  parameter int ADDR_WIDTH = 24,
  parameter int DATA_WIDTH = 32
);
  logic [ADDR_WIDTH-1:0] addr;
  logic [15:0] length;
  logic read_req;
  logic read_en;
  logic busy;
  logic done;
  logic error;
  logic [DATA_WIDTH-1:0] read_data;
  logic [DATA_WIDTH-1:0] data_out;

  modport master (
    output addr, length, read_req, read_en,
    input  busy, done, error, read_data
  );

  modport slave (
    input  addr, length, read_req, read_en,
    output busy, done, error, read_data
  );
endinterface
