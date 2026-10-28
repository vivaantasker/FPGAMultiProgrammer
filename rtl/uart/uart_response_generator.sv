`timescale 1ns/1ps

module uart_response_generator #(
  parameter int MAX_PAYLOAD = 32
)(
  input  logic clk,
  input  logic rst_n,
  input  logic trigger,
  input  logic [7:0] response_id,
  input  logic [7:0] error_code,
  input  logic [7:0] payload [0:MAX_PAYLOAD-1],
  input  logic [7:0] payload_len,
  output logic tx_valid,
  output logic [7:0] tx_data,
  output logic tx_busy
);
  // Purpose: construct UART response packets from controller events.
  // Inputs: clk, rst_n, trigger, response_id, error_code, payload, payload_len
  // Outputs: tx_valid, tx_data, tx_busy
  // Clock/reset: clk, rst_n
  // Assumption: the packet generator emits one byte per cycle and is consumed by an external UART TX block.

  logic [7:0] packet [0:255];
  logic [7:0] send_count;
  logic [7:0] packet_len;
  logic [15:0] crc_acc;
  logic active;

  function automatic logic [15:0] crc16_update(input logic [15:0] crc_in, input logic [7:0] data);
    logic [15:0] crc;
    crc = crc_in;
    for (int i = 0; i < 8; i++) begin
      crc = {crc[14:0], 1'b0};
      if ((data[i] ^ crc[15]) == 1'b1) begin
        crc = crc ^ 16'h1021;
      end
    end
    return crc;
  endfunction

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      tx_valid <= 1'b0;
      tx_data <= 8'h00;
      tx_busy <= 1'b0;
      send_count <= '0;
      packet_len <= '0;
      active <= 1'b0;
      crc_acc <= 16'hFFFF;
      for (int i = 0; i < 256; i++) packet[i] <= 8'h00;
    end else if (trigger && !active) begin
      active <= 1'b1;
      tx_busy <= 1'b1;
      packet[0] <= 8'hAA;
      packet[1] <= response_id;
      packet[2] <= payload_len[7:0];
      for (int i = 0; i < 256; i++) packet[3 + i] <= 8'h00;
      for (int i = 0; i < payload_len; i++) begin
        packet[3 + i] <= payload[i];
      end
      crc_acc <= 16'hFFFF;
      crc_acc <= crc16_update(crc_acc, response_id);
      crc_acc <= crc16_update(crc_acc, payload_len);
      for (int i = 0; i < payload_len; i++) begin
        crc_acc <= crc16_update(crc_acc, payload[i]);
      end
      packet[3 + payload_len] <= crc_acc[15:8];
      packet[4 + payload_len] <= crc_acc[7:0];
      packet[5 + payload_len] <= 8'h55;
      send_count <= 0;
      packet_len <= 5 + payload_len;
      tx_valid <= 1'b1;
      tx_data <= packet[0];
    end else if (active && tx_valid) begin
      if (send_count < packet_len - 1) begin
        send_count <= send_count + 1'b1;
        tx_data <= packet[send_count + 1'b1];
      end else begin
        active <= 1'b0;
        tx_busy <= 1'b0;
        tx_valid <= 1'b0;
      end
    end else begin
      tx_valid <= 1'b0;
    end
  end
endmodule
