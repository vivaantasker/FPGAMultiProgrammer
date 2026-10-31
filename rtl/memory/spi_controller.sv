`timescale 1ns/1ps

module spi_controller #(
  parameter int ADDR_WIDTH = 24,
  parameter int DATA_WIDTH = 32,
  parameter int CLK_FREQ_HZ = 100_000_000,
  parameter int SCLK_FREQ_HZ = 10_000_000,
  parameter int DUMMY_CYCLES = 0,
  parameter logic [7:0] READ_OPCODE = 8'h03
)(
  input  logic clk,
  input  logic rst_n,
  input  logic [ADDR_WIDTH-1:0] addr,
  input  logic [31:0] length,
  input  logic read_req,
  input  logic abort = 1'b0,
  input  logic [7:0] cfg_read_opcode = READ_OPCODE,
  input  logic [15:0] cfg_dummy_cycles = DUMMY_CYCLES,
  input  logic [15:0] cfg_clk_divider = ((CLK_FREQ_HZ / (2 * SCLK_FREQ_HZ)) < 1) ? 16'd1 : (CLK_FREQ_HZ / (2 * SCLK_FREQ_HZ)),
  output logic busy,
  output logic done,
  output logic error,
  output logic [DATA_WIDTH-1:0] read_data,
  output logic [DATA_WIDTH-1:0] m_axis_tdata,
  output logic [DATA_WIDTH/8-1:0] m_axis_tkeep,
  output logic m_axis_tvalid,
  input  logic m_axis_tready = 1'b1,
  output logic m_axis_tlast,
  output logic sclk,
  output logic cs_n,
  output logic mosi,
  input  logic miso
);
  // Generic SPI-NOR 1-1-1 read profile. Opcode, SCLK rate, and dummy
  // cycles are parameters so the controller is not tied to one flash part.
  // length is the number of bits to read and must be non-zero.
  logic [0:0] io_out;
  logic io_oe;

  assign mosi = io_oe ? io_out[0] : 1'b0;

  serial_flash_read_engine #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH),
    .LANES(1),
    .CMD_LANES(1),
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
    .abort(abort),
    .cfg_read_opcode(cfg_read_opcode),
    .cfg_dummy_cycles(cfg_dummy_cycles),
    .cfg_clk_divider(cfg_clk_divider),
    .busy(busy),
    .done(done),
    .error(error),
    .read_data(read_data),
    .m_axis_tdata(m_axis_tdata),
    .m_axis_tkeep(m_axis_tkeep),
    .m_axis_tvalid(m_axis_tvalid),
    .m_axis_tready(m_axis_tready),
    .m_axis_tlast(m_axis_tlast),
    .sclk(sclk),
    .cs_n(cs_n),
    .io_in(miso),
    .io_out(io_out),
    .io_oe(io_oe)
  );
endmodule
