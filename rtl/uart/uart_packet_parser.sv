`timescale 1ns/1ps

import programmer_pkg::*;

module uart_packet_parser #(
  parameter int MAX_PAYLOAD = 256
)(
  input  logic clk,
  input  logic rst_n,
  input  logic rx_valid,
  input  logic [7:0] rx_data,
  output logic packet_valid,
  output logic packet_error,
  output logic [7:0] command,
  output logic [15:0] length,
  output logic [7:0] payload [0:MAX_PAYLOAD-1],
  output logic [15:0] crc_value,
  output logic [7:0] error_code
);
  // Purpose: decode UART packet into command, length, payload, and CRC.
  // Inputs: clk, rst_n, rx_valid, rx_data
  // Outputs: packet_valid, packet_error, command, length, payload, crc_value, error_code
  // Clock/reset: clk, rst_n
  // Assumption: packet format is SOF | CMD | LENGTH | PAYLOAD | CRC16 | EOF.

  typedef enum logic [3:0] { S_IDLE, S_SOF, S_CMD, S_LEN_MSB, S_LEN_LSB, S_PAYLOAD, S_CRC_MSB, S_CRC_LSB, S_EOF, S_ERROR } state_t;
  state_t state;
  logic [15:0] crc_acc;
  logic [7:0] payload_count;
  logic [7:0] rx_byte;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      packet_valid <= 1'b0;
      packet_error <= 1'b0;
      command <= 8'h00;
      length <= '0;
      crc_value <= '0;
      error_code <= 8'h00;
      state <= S_IDLE;
      crc_acc <= 16'hFFFF;
      payload_count <= '0;
      for (int i = 0; i < MAX_PAYLOAD; i++) payload[i] <= 8'h00;
    end else if (rx_valid) begin
      rx_byte <= rx_data;
      case (state)
        S_IDLE: begin
          packet_valid <= 1'b0;
          packet_error <= 1'b0;
          if (rx_data == 8'hAA) begin
            state <= S_CMD;
            crc_acc <= 16'hFFFF;
          end else begin
            packet_error <= 1'b1;
            error_code <= 8'h01; // bad SOF
            state <= S_ERROR;
          end
        end
        S_CMD: begin
          command <= rx_data;
          state <= S_LEN_MSB;
          crc_acc <= programmer_pkg::crc16_update(crc_acc, rx_data);
        end
        S_LEN_MSB: begin
          length[15:8] <= rx_data;
          state <= S_LEN_LSB;
          crc_acc <= programmer_pkg::crc16_update(crc_acc, rx_data);
        end
        S_LEN_LSB: begin
          length[7:0] <= rx_data;
          payload_count <= '0;
          state <= (rx_data == 0) ? S_CRC_MSB : S_PAYLOAD;
          crc_acc <= programmer_pkg::crc16_update(crc_acc, rx_data);
        end
        S_PAYLOAD: begin
          if (payload_count < length[7:0]) begin
            payload[payload_count] <= rx_data;
            payload_count <= payload_count + 1'b1;
            crc_acc <= programmer_pkg::crc16_update(crc_acc, rx_data);
            if (payload_count == length[7:0] - 1) state <= S_CRC_MSB;
          end else begin
            state <= S_ERROR;
            packet_error <= 1'b1;
            error_code <= 8'h03;
          end
        end
        S_CRC_MSB: begin
          crc_value[15:8] <= rx_data;
          state <= S_CRC_LSB;
          crc_acc <= programmer_pkg::crc16_update(crc_acc, rx_data);
        end
        S_CRC_LSB: begin
          crc_value[7:0] <= rx_data;
          state <= S_EOF;
          crc_acc <= programmer_pkg::crc16_update(crc_acc, rx_data);
        end
        S_EOF: begin
          if (rx_data == 8'h55) begin
            if (crc_acc == 16'h0000) begin
              packet_valid <= 1'b1;
              packet_error <= 1'b0;
            end else begin
              packet_error <= 1'b1;
              error_code <= 8'h04; // CRC failure
            end
            state <= S_IDLE;
          end else begin
            packet_error <= 1'b1;
            error_code <= 8'h02; // bad EOF
            state <= S_ERROR;
          end
        end
        S_ERROR: begin
          packet_valid <= 1'b0;
          packet_error <= 1'b1;
          state <= S_IDLE;
        end
        default: state <= S_IDLE;
      endcase
    end
  end
endmodule
