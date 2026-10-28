`timescale 1ns/1ps

module timeout_manager #(
  parameter int COUNT_WIDTH = 32
)(
  input  logic clk,
  input  logic rst_n,
  input  logic start_timer,
  input  logic clear_timer,
  input  logic [COUNT_WIDTH-1:0] timeout_value,
  output logic timeout_event,
  output logic timer_active
);
  // Purpose: watchdog timer for memory, DMA, JTAG, and program operations.
  // Inputs: clk, rst_n, start_timer, clear_timer, timeout_value
  // Outputs: timeout_event, timer_active
  // Clock/reset: clk, rst_n
  // Assumption: one active timeout window at a time; value is a number of ticks.

  logic [COUNT_WIDTH-1:0] count;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      count <= '0;
      timeout_event <= 1'b0;
      timer_active <= 1'b0;
    end else begin
      timeout_event <= 1'b0;
      if (start_timer) begin
        count <= timeout_value;
        timer_active <= 1'b1;
      end else if (clear_timer) begin
        count <= '0;
        timer_active <= 1'b0;
      end else if (timer_active) begin
        if (count == '0) begin
          timeout_event <= 1'b1;
          timer_active <= 1'b0;
        end else begin
          count <= count - 1'b1;
        end
      end
    end
  end
endmodule
