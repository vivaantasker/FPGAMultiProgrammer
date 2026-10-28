`timescale 1ns/1ps

module uart_protocol #(
  parameter int CLK_FREQ_HZ = 100_000_000,
  parameter int BAUD_RATE   = 115_200,
  parameter int MAX_PAYLOAD = 256
)(
  input  logic clk,
  input  logic rst_n,
  input  logic rx,
  output logic tx,
  output logic packet_valid,
  output logic packet_error,
  output logic [7:0] command,
  output logic [15:0] length,
  output logic [7:0] payload [0:MAX_PAYLOAD-1],
  output logic [15:0] crc_value,
  output logic [7:0] error_code,
  input  logic response_trigger,
  input  logic [7:0] response_id,
  input  logic [7:0] response_payload [0:MAX_PAYLOAD-1],
  input  logic [7:0] response_len,
  input  logic [7:0] response_error,
  output logic response_busy
);
  // Purpose: UART receive parser + response generator glue logic.
  // Inputs: clk, rst_n, rx, response_trigger, response_id, response_payload, response_len, response_error
  // Outputs: tx, packet_valid, packet_error, command, length, payload, crc_value, error_code, response_busy
  // Clock/reset: clk, rst_n
  // Assumption: packet parsing is packet-oriented and response generation is driven by controller events.

  logic [7:0] rx_byte;
  logic rx_valid;
  logic tx_valid;
  logic [7:0] tx_byte;
  logic tx_busy;

  uart_rx #(.CLK_FREQ_HZ(CLK_FREQ_HZ), .BAUD_RATE(BAUD_RATE)) u_uart_rx (
    .clk(clk),
    .rst_n(rst_n),
    .rx(rx),
    .data_out(rx_byte),
    .data_valid(rx_valid),
    .frame_error()
  );

  uart_packet_parser #(.MAX_PAYLOAD(MAX_PAYLOAD)) u_parser (
    .clk(clk),
    .rst_n(rst_n),
    .rx_valid(rx_valid),
    .rx_data(rx_byte),
    .packet_valid(packet_valid),
    .packet_error(packet_error),
    .command(command),
    .length(length),
    .payload(payload),
    .crc_value(crc_value),
    .error_code(error_code)
  );

  uart_response_generator #(.MAX_PAYLOAD(MAX_PAYLOAD)) u_resp (
    .clk(clk),
    .rst_n(rst_n),
    .trigger(response_trigger),
    .response_id(response_id),
    .error_code(response_error),
    .payload(response_payload),
    .payload_len(response_len),
    .tx_valid(tx_valid),
    .tx_data(tx_byte),
    .tx_busy(response_busy)
  );

  uart_tx #(.CLK_FREQ_HZ(CLK_FREQ_HZ), .BAUD_RATE(BAUD_RATE)) u_uart_tx (
    .clk(clk),
    .rst_n(rst_n),
    .tx_data(tx_byte),
    .tx_valid(tx_valid),
    .tx_busy(tx_busy),
    .tx(tx)
  );
endmodule
