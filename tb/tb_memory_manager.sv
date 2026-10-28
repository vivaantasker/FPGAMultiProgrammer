`timescale 1ns/1ps

module tb_memory_manager;
  logic clk = 0;
  logic rst_n = 0;
  logic [2:0] memory_type = 3'd0;
  logic [23:0] addr = 24'd0;
  logic [15:0] length = 16'd4;
  logic read_req = 0;
  logic busy, done, error;
  logic [31:0] read_data;
  logic sclk, cs_n, mosi;
  logic miso = 1'b0;
  logic qspi_sclk, qspi_cs_n;
  tri [3:0] qspi_io;
  logic ospi_sclk, ospi_cs_n;
  tri [7:0] ospi_io;

  memory_manager #(.ADDR_WIDTH(24), .DATA_WIDTH(32), .MEM_TYPE_WIDTH(3)) dut (
    .clk(clk),
    .rst_n(rst_n),
    .memory_type(memory_type),
    .addr(addr),
    .length(length),
    .read_req(read_req),
    .busy(busy),
    .done(done),
    .error(error),
    .read_data(read_data),
    .sclk(sclk),
    .cs_n(cs_n),
    .mosi(mosi),
    .miso(miso),
    .qspi_sclk(qspi_sclk),
    .qspi_cs_n(qspi_cs_n),
    .qspi_io(qspi_io),
    .ospi_sclk(ospi_sclk),
    .ospi_cs_n(ospi_cs_n),
    .ospi_io(ospi_io)
  );

  always #5 clk = ~clk;

  initial begin
    #20 rst_n = 1;
    #20 read_req = 1;
    #40 read_req = 0;
    #200 $finish;
  end
endmodule
