`timescale 1ns/1ps

module ospi_controller #(
  parameter int ADDR_WIDTH = 24,
  parameter int DATA_WIDTH = 32,
  parameter int CLK_FREQ_HZ = 100_000_000,
  parameter int SCLK_FREQ_HZ = 10_000_000,
  parameter int DUMMY_CYCLES = 2,
  parameter logic [7:0] READ_OPCODE = 8'hEC
)(
  input  logic clk,
  input  logic rst_n,
  input  logic [ADDR_WIDTH-1:0] addr,
  input  logic [15:0] length,
  input  logic read_req,
  input  logic [7:0] cfg_read_opcode = READ_OPCODE,
  input  logic [15:0] cfg_dummy_cycles = DUMMY_CYCLES,
  input  logic [15:0] cfg_clk_divider = ((CLK_FREQ_HZ / (2 * SCLK_FREQ_HZ)) < 1) ? 16'd1 : (CLK_FREQ_HZ / (2 * SCLK_FREQ_HZ)),
  output logic busy,
  output logic done,
  output logic error,
  output logic [DATA_WIDTH-1:0] read_data,
  output logic sclk,
  output logic cs_n,
  inout  wire [7:0] io
);
  logic [7:0] io_in;
  logic [7:0] io_out;
  logic io_oe;

  assign io = io_oe ? io_out : 8'bz;
  assign io_in = io;

  // Generic SDR octal-read profile: one octal command cycle, then octal
  // address and data. Flash-specific command and dummy timing are parameters.
  serial_flash_read_engine #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH),
    .LANES(8),
    .CMD_LANES(8),
    .CLK_FREQ_HZ(CLK_FREQ_HZ),
    .SERIAL_CLK_HZ(SCLK_FREQ_HZ),
    .DUMMY_CYCLES(DUMMY_CYCLES),
    .READ_OPCODE(READ_OPCODE)
  ) u_read_engine (
    .clk(clk),
    .rst_n(rst_n),
    .addr(addr),
    .length(length),
    .read_req(read_req),
    .cfg_read_opcode(cfg_read_opcode),
    .cfg_dummy_cycles(cfg_dummy_cycles),
    .cfg_clk_divider(cfg_clk_divider),
    .busy(busy),
    .done(done),
    .error(error),
    .read_data(read_data),
    .sclk(sclk),
    .cs_n(cs_n),
    .io_in(io_in),
    .io_out(io_out),
    .io_oe(io_oe)
  );
endmodule
