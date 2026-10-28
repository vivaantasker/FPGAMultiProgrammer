`timescale 1ns/1ps

module uart_tx #(
  parameter int CLK_FREQ_HZ = 100_000_000,
  parameter int BAUD_RATE   = 115_200
)(
  input  logic clk,
  input  logic rst_n,
  input  logic [7:0] tx_data,
  input  logic tx_valid,
  output logic tx_busy,
  output logic tx
);
  // Purpose: transmit UART bytes with no flow control beyond tx_valid.
  // Inputs: clk, rst_n, tx_data, tx_valid
  // Outputs: tx_busy, tx
  // Clock/reset: clk, rst_n
  // Assumption: 8-N-1 UART format.

  localparam int BAUD_DIV = CLK_FREQ_HZ / BAUD_RATE;
  typedef enum logic [2:0] { IDLE, START, DATA, STOP } state_t;

  state_t state;
  logic [$clog2(BAUD_DIV):0] bit_time;
  logic [3:0] bit_index;
  logic [7:0] shift_reg;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= IDLE;
      bit_time <= '0;
      bit_index <= '0;
      shift_reg <= '0;
      tx <= 1'b1;
      tx_busy <= 1'b0;
    end else begin
      case (state)
        IDLE: begin
          tx <= 1'b1;
          if (tx_valid) begin
            shift_reg <= tx_data;
            tx_busy <= 1'b1;
            bit_index <= '0;
            bit_time <= 0;
            state <= START;
          end
        end
        START: begin
          tx <= 1'b0;
          if (bit_time == BAUD_DIV-1) begin
            bit_time <= '0;
            state <= DATA;
          end else begin
            bit_time <= bit_time + 1'b1;
          end
        end
        DATA: begin
          tx <= shift_reg[bit_index];
          if (bit_time == BAUD_DIV-1) begin
            bit_time <= '0;
            bit_index <= bit_index + 1'b1;
            if (bit_index == 7) state <= STOP;
          end else begin
            bit_time <= bit_time + 1'b1;
          end
        end
        STOP: begin
          tx <= 1'b1;
          if (bit_time == BAUD_DIV-1) begin
            tx_busy <= 1'b0;
            state <= IDLE;
            bit_time <= '0;
          end else begin
            bit_time <= bit_time + 1'b1;
          end
        end
        default: state <= IDLE;
      endcase
    end
  end
endmodule
