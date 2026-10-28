`timescale 1ns/1ps

module jtag_shift_engine #(
  parameter int DATA_WIDTH = 32
)(
  input  logic clk,
  input  logic rst_n,
  input  logic shift_enable,
  input  logic [DATA_WIDTH-1:0] tdi_word,
  input  logic [DATA_WIDTH-1:0] tdo_word,
  output logic [DATA_WIDTH-1:0] shift_tdo,
  output logic [DATA_WIDTH-1:0] shift_tdi
);
  // Purpose: shift a word into and out of the JTAG chain.
  // Inputs: clk, rst_n, shift_enable, tdi_word, tdo_word
  // Outputs: shift_tdo, shift_tdi
  // Clock/reset: clk, rst_n
  // Assumption: only one word is shifted at a time and the engine is driven by the TAP state machine.

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      shift_tdo <= '0;
      shift_tdi <= '0;
    end else if (shift_enable) begin
      shift_tdi <= tdi_word;
      shift_tdo <= tdo_word;
    end
  end
endmodule
