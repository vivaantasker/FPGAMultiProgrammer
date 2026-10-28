`timescale 1ns/1ps

module tb_fpga_programmer;
  logic clk = 0;
  logic rst_n = 0;
  logic uart_rx = 1;
  logic uart_tx;
  logic [7:0] led;
  logic [7:0] gpio_in = 8'h00;
  logic [7:0] gpio_out;
  logic tdo = 1'b0;
  logic tck, tms, tdi;
  logic sclk, cs_n, mosi;
  logic miso = 1'b0;
  logic qspi_sclk, qspi_cs_n;
  tri [3:0] qspi_io;
  logic ospi_sclk, ospi_cs_n;
  tri [7:0] ospi_io;

  fpga_programmer_top dut (
    .clk(clk),
    .rst_n(rst_n),
    .uart_rx(uart_rx),
    .uart_tx(uart_tx),
    .led(led),
    .gpio_in(gpio_in),
    .gpio_out(gpio_out),
    .tdo(tdo),
    .tck(tck),
    .tms(tms),
    .tdi(tdi),
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
    #500 $finish;
  end
endmodule
