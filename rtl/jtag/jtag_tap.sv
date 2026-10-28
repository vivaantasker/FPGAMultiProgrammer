`timescale 1ns/1ps

module jtag_tap (
  input  logic clk,
  input  logic rst_n,
  input  logic tms,
  input  logic tdi,
  output logic tdo,
  output logic [3:0] tap_state
);
  // Purpose: TAP controller state machine for standard JTAG operations.
  // Inputs: clk, rst_n, tms, tdi
  // Outputs: tdo, tap_state
  // Clock/reset: clk, rst_n
  // Assumption: a simple finite state machine implements the standard JTAG states.

  import programmer_pkg::*;

  tap_state_t current_state;
  tap_state_t next_state;

  assign tap_state = current_state;

  always_comb begin
    next_state = current_state;
    case (current_state)
      TAP_TEST_LOGIC_RESET: next_state = tms ? TAP_TEST_LOGIC_RESET : TAP_RUN_TEST_IDLE;
      TAP_RUN_TEST_IDLE: next_state = tms ? TAP_SELECT_DR_SCAN : TAP_RUN_TEST_IDLE;
      TAP_SELECT_DR_SCAN: next_state = tms ? TAP_SELECT_IR_SCAN : TAP_CAPTURE_DR;
      TAP_CAPTURE_DR: next_state = tms ? TAP_EXIT1_DR : TAP_SHIFT_DR;
      TAP_SHIFT_DR: next_state = tms ? TAP_EXIT1_DR : TAP_SHIFT_DR;
      TAP_EXIT1_DR: next_state = tms ? TAP_UPDATE_DR : TAP_PAUSE_DR;
      TAP_PAUSE_DR: next_state = tms ? TAP_EXIT2_DR : TAP_PAUSE_DR;
      TAP_EXIT2_DR: next_state = tms ? TAP_UPDATE_DR : TAP_SHIFT_DR;
      TAP_UPDATE_DR: next_state = tms ? TAP_SELECT_DR_SCAN : TAP_RUN_TEST_IDLE;
      TAP_SELECT_IR_SCAN: next_state = tms ? TAP_TEST_LOGIC_RESET : TAP_CAPTURE_IR;
      TAP_CAPTURE_IR: next_state = tms ? TAP_EXIT1_IR : TAP_SHIFT_IR;
      TAP_SHIFT_IR: next_state = tms ? TAP_EXIT1_IR : TAP_SHIFT_IR;
      TAP_EXIT1_IR: next_state = tms ? TAP_UPDATE_IR : TAP_PAUSE_IR;
      TAP_PAUSE_IR: next_state = tms ? TAP_EXIT2_IR : TAP_PAUSE_IR;
      TAP_EXIT2_IR: next_state = tms ? TAP_UPDATE_IR : TAP_SHIFT_IR;
      TAP_UPDATE_IR: next_state = tms ? TAP_SELECT_DR_SCAN : TAP_RUN_TEST_IDLE;
      default: next_state = TAP_TEST_LOGIC_RESET;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      current_state <= TAP_TEST_LOGIC_RESET;
      tdo <= 1'b0;
    end else begin
      current_state <= next_state;
      tdo <= tdi;
    end
  end
endmodule
