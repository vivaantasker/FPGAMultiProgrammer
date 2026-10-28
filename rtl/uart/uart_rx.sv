`timescale 1ns/1ps

module uart_rx #(
  parameter int CLK_FREQ_HZ = 100_000_000,
  parameter int BAUD_RATE   = 115_200
)(
  input  logic clk,
  input  logic rst_n,
  input  logic rx,
  output logic [7:0] data_out,
  output logic data_valid,
  output logic frame_error
);
  // Purpose: receive UART bytes with a simple baud-rate oversampling state machine.
  // Inputs: clk, rst_n, rx
  // Outputs: data_out, data_valid, frame_error
  // Clock/reset: clk, rst_n
  // Assumption: 8-N-1 UART format with one start bit and one stop bit.

  localparam int BAUD_DIV = CLK_FREQ_HZ / BAUD_RATE;
  localparam int HALF_DIV = BAUD_DIV / 2;

  typedef enum logic [2:0] { IDLE, START, DATA, STOP } state_t;
  state_t state;
  logic [$clog2(BAUD_DIV):0] tick_count;
  logic [3:0] bit_count;
  logic [7:0] shift_reg;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= IDLE;
      tick_count <= '0;
      bit_count <= '0;
      shift_reg <= '0;
      data_out <= '0;
      data_valid <= 1'b0;
      frame_error <= 1'b0;
    end else begin
      data_valid <= 1'b0;
      case (state)
        IDLE: begin
          if (rx == 1'b0) begin
            state <= START;
            tick_count <= HALF_DIV;
          end
        end
        START: begin
          if (tick_count == 0) begin
            state <= DATA;
            bit_count <= 0;
            tick_count <= BAUD_DIV;
          end else begin
            tick_count <= tick_count - 1'b1;
          end
        end
        DATA: begin
          if (tick_count == 0) begin
            shift_reg[bit_count] <= rx;
            bit_count <= bit_count + 1'b1;
            if (bit_count == 7) begin
              state <= STOP;
            end
            tick_count <= BAUD_DIV;
          end else begin
            tick_count <= tick_count - 1'b1;
          end
        end
        STOP: begin
          if (tick_count == 0) begin
            data_out <= shift_reg;
            data_valid <= 1'b1;
            frame_error <= (rx == 1'b0);
            state <= IDLE;
            tick_count <= '0;
          end else begin
            tick_count <= tick_count - 1'b1;
          end
        end
        default: state <= IDLE;
      endcase
    end
  end
endmodule
