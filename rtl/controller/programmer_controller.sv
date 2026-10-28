`timescale 1ns/1ps

module programmer_controller #(
  parameter int AXI_ADDR_WIDTH = 32,
  parameter int AXI_DATA_WIDTH = 32,
  parameter int STREAM_DATA_WIDTH = 32
)(
  input  logic clk,
  input  logic rst_n,
  input  logic packet_valid,
  input  logic packet_error,
  input  logic [7:0] command,
  input  logic [15:0] length,
  input  logic [7:0] payload [0:255],
  input  logic [15:0] crc_value,
  input  logic [7:0] error_code,
  output logic response_trigger,
  output logic [7:0] response_id,
  output logic [7:0] response_payload [0:255],
  output logic [7:0] response_len,
  output logic [7:0] response_error,
  output logic [2:0] memory_type,
  output logic [AXI_ADDR_WIDTH-1:0] memory_address,
  output logic [31:0] bitstream_length,
  output logic [31:0] expected_idcode,
  output logic [31:0] jtag_frequency,
  output logic [7:0] jtag_mode,
  output logic [2:0] trigger_type,
  output logic [15:0] bitstream_id,
  output logic [7:0] flags,
  input  logic memory_done,
  input  logic memory_error,
  input  logic dma_done,
  input  logic dma_error,
  input  logic jtag_done,
  input  logic jtag_error,
  input  logic idcode_ready,
  input  logic [31:0] idcode_value,
  output logic start_dma,
  output logic abort_dma,
  output logic start_jtag,
  output logic abort_jtag,
  output logic controller_busy,
  output logic [3:0] state_out
);
  // Purpose: hardware FSM controlling configuration, memory access, DMA, and JTAG programming.
  // Inputs: clk, rst_n, packet_valid, packet_error, command, length, payload, error_code, peripheral completions
  // Outputs: response_trigger, response_id, response_payload, response_len, memory configuration, DMA/JTAG start signals, controller state
  // Clock/reset: clk, rst_n
  // Assumption: UART packet decoding is already validated by uart_protocol; this block performs control-plane sequencing.

  import programmer_pkg::*;

  controller_state_t state;
  logic config_received;
  logic valid_config;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= CTRL_IDLE;
      response_trigger <= 1'b0;
      response_id <= RESP_ACK;
      response_len <= '0;
      response_error <= '0;
      memory_type <= MEM_SPI;
      memory_address <= '0;
      bitstream_length <= '0;
      expected_idcode <= '0;
      jtag_frequency <= 32'd100000;
      jtag_mode <= '0;
      trigger_type <= TRIG_MANUAL;
      bitstream_id <= '0;
      flags <= '0;
      start_dma <= 1'b0;
      abort_dma <= 1'b0;
      start_jtag <= 1'b0;
      abort_jtag <= 1'b0;
      controller_busy <= 1'b0;
      config_received <= 1'b0;
      valid_config <= 1'b0;
      state_out <= CTRL_IDLE;
      for (int i = 0; i < 256; i++) response_payload[i] <= 8'h00;
    end else begin
      response_trigger <= 1'b0;
      start_dma <= 1'b0;
      abort_dma <= 1'b0;
      start_jtag <= 1'b0;
      abort_jtag <= 1'b0;

      case (state)
        CTRL_IDLE: begin
          controller_busy <= 1'b0;
          if (packet_valid && !packet_error) begin
            if (command == CMD_CONFIGURE) begin
              config_received <= 1'b1;
              valid_config <= 1'b1;
              memory_type <= payload[0][2:0];
              memory_address <= {payload[1], payload[2], payload[3], payload[4]};
              bitstream_length <= {payload[5], payload[6], payload[7], payload[8]};
              expected_idcode <= {payload[9], payload[10], payload[11], payload[12]};
              jtag_frequency <= {payload[13], payload[14], payload[15], payload[16]};
              jtag_mode <= payload[17];
              trigger_type <= payload[18][2:0];
              bitstream_id <= {payload[19], payload[20]};
              flags <= payload[21];
              response_id <= RESP_ACK;
              response_len <= 8'd1;
              response_payload[0] <= 8'd1;
              response_trigger <= 1'b1;
              state <= CTRL_MEMORY_CONFIG;
            end else if (command == CMD_START) begin
              state <= CTRL_START_TRANSFER;
            end else if (command == CMD_ABORT) begin
              state <= CTRL_ABORT;
            end else begin
              response_id <= RESP_NACK;
              response_error <= 8'd5;
              state <= CTRL_ERROR;
            end
          end else if (packet_error) begin
            response_id <= RESP_NACK;
            response_error <= error_code;
            response_len <= 8'd1;
            response_payload[0] <= error_code;
            response_trigger <= 1'b1;
            state <= CTRL_ERROR;
          end
        end

        CTRL_MEMORY_CONFIG: begin
          controller_busy <= 1'b1;
          if (config_received && valid_config) begin
            response_id <= RESP_STATUS;
            response_len <= 8'd1;
            response_payload[0] <= 8'd1;
            response_trigger <= 1'b1;
            state <= CTRL_DMA_CONFIG;
          end else begin
            response_id <= RESP_NACK;
            response_error <= 8'd1;
            response_trigger <= 1'b1;
            state <= CTRL_ERROR;
          end
        end

        CTRL_DMA_CONFIG: begin
          start_dma <= 1'b1;
          state <= CTRL_JTAG_CONFIG;
        end

        CTRL_JTAG_CONFIG: begin
          start_jtag <= 1'b1;
          state <= CTRL_START_TRANSFER;
        end

        CTRL_START_TRANSFER: begin
          controller_busy <= 1'b1;
          if (memory_done) begin
            response_id <= RESP_PROGRAM_STARTED;
            response_len <= 8'd1;
            response_payload[0] <= 8'd1;
            response_trigger <= 1'b1;
            state <= CTRL_WAIT_TRANSFER;
          end
        end

        CTRL_WAIT_TRANSFER: begin
          if (dma_done) begin
            state <= CTRL_VERIFY;
          end else if (dma_error || memory_error || jtag_error) begin
            response_id <= RESP_PROGRAM_ERROR;
            response_error <= 8'd1;
            response_trigger <= 1'b1;
            state <= CTRL_ERROR;
          end
        end

        CTRL_VERIFY: begin
          if (idcode_ready) begin
            if (idcode_value == expected_idcode) begin
              response_id <= RESP_PROGRAM_COMPLETE;
              response_len <= 8'd1;
              response_payload[0] <= 8'd1;
              response_trigger <= 1'b1;
              state <= CTRL_REPORT_SUCCESS;
            end else begin
              response_id <= RESP_PROGRAM_ERROR;
              response_error <= 8'd11;
              response_trigger <= 1'b1;
              state <= CTRL_ERROR;
            end
          end
        end

        CTRL_REPORT_SUCCESS: begin
          controller_busy <= 1'b0;
          state <= CTRL_IDLE;
        end

        CTRL_ERROR: begin
          controller_busy <= 1'b0;
          response_id <= RESP_PROGRAM_ERROR;
          response_trigger <= 1'b1;
          state <= CTRL_IDLE;
        end

        CTRL_ABORT: begin
          abort_dma <= 1'b1;
          abort_jtag <= 1'b1;
          response_id <= RESP_NACK;
          response_error <= 8'd12;
          response_trigger <= 1'b1;
          state <= CTRL_IDLE;
        end

        CTRL_RESET_PERIPHERALS: begin
          abort_dma <= 1'b1;
          abort_jtag <= 1'b1;
          state <= CTRL_IDLE;
        end

        default: state <= CTRL_IDLE;
      endcase

      state_out <= state;
    end
  end
endmodule
