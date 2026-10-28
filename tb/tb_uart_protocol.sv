`timescale 1ns/1ps

module tb_uart_protocol;
  logic clk = 0;
  logic rst_n = 0;
  logic rx = 1;
  logic tx;
  logic packet_valid;
  logic packet_error;
  logic [7:0] command;
  logic [15:0] length;
  logic [7:0] payload [0:255];
  logic [15:0] crc_value;
  logic [7:0] error_code;
  logic response_trigger;
  logic [7:0] response_id;
  logic [7:0] response_payload [0:255];
  logic [7:0] response_len;
  logic [7:0] response_error;
  logic response_busy;

  uart_protocol #(.CLK_FREQ_HZ(100_000_000), .BAUD_RATE(115_200), .MAX_PAYLOAD(256)) dut (
    .clk(clk),
    .rst_n(rst_n),
    .rx(rx),
    .tx(tx),
    .packet_valid(packet_valid),
    .packet_error(packet_error),
    .command(command),
    .length(length),
    .payload(payload),
    .crc_value(crc_value),
    .error_code(error_code),
    .response_trigger(response_trigger),
    .response_id(response_id),
    .response_payload(response_payload),
    .response_len(response_len),
    .response_error(response_error),
    .response_busy(response_busy)
  );

  always #5 clk = ~clk;

  initial begin
    #20 rst_n = 1;
    #100;
    response_trigger = 1;
    response_id = 8'h01;
    response_len = 8'd1;
    response_payload[0] = 8'd1;
    response_error = 8'h00;
    #20 response_trigger = 0;
    #200 $finish;
  end
endmodule
