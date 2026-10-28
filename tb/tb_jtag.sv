`timescale 1ns/1ps

module tb_jtag;
  logic clk = 0;
  logic rst_n = 0;
  logic [31:0] jtag_frequency = 32'd100000;
  logic [31:0] expected_idcode = 32'h12345678;
  logic [31:0] ir_length = 32'd32;
  logic [31:0] dr_length = 32'd32;
  logic [31:0] tx_data = 32'hA5A5A5A5;
  logic tx_valid = 0;
  logic tx_ready;
  logic [31:0] rx_data;
  logic rx_valid;
  logic [31:0] idcode;
  logic idcode_ready;
  logic [15:0] status;
  logic [15:0] error_code;
  logic tck;
  logic tms;
  logic tdi;
  logic tdo = 1'b0;

  jtag_controller #(.DATA_WIDTH(32), .MAX_IR_LENGTH(32), .MAX_DR_LENGTH(1024)) dut (
    .clk(clk),
    .rst_n(rst_n),
    .jtag_frequency(jtag_frequency),
    .expected_idcode(expected_idcode),
    .ir_length(ir_length),
    .dr_length(dr_length),
    .tx_data(tx_data),
    .tx_valid(tx_valid),
    .tx_ready(tx_ready),
    .rx_data(rx_data),
    .rx_valid(rx_valid),
    .idcode(idcode),
    .idcode_ready(idcode_ready),
    .status(status),
    .error_code(error_code),
    .tck(tck),
    .tms(tms),
    .tdi(tdi),
    .tdo(tdo)
  );

  always #5 clk = ~clk;

  initial begin
    #20 rst_n = 1;
    #40 tx_valid = 1;
    #80 tx_valid = 0;
    #200 $finish;
  end
endmodule
