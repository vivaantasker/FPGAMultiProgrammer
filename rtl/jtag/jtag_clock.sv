`timescale 1ns/1ps

module jtag_clock #(
  parameter int CLK_FREQ_HZ = 100_000_000,
  parameter int TCK_DIV_MAX = 64
)(
  input  logic clk,
  input  logic rst_n,
  input  logic [31:0] jtag_frequency,
  output logic tck
);
  // Purpose: generate the JTAG TCK from the system clock using a programmable divider.
  // Inputs: clk, rst_n, jtag_frequency
  // Outputs: tck
  // Clock/reset: clk, rst_n
  // Assumption: tck is a lower-frequency clock derived from the main system clock.

  logic [31:0] divide_count;
  logic [31:0] divisor;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      divide_count <= '0;
      tck <= 1'b0;
      divisor <= 32'd10;
    end else begin
      divisor <= (jtag_frequency == 0) ? 32'd10 : (CLK_FREQ_HZ / jtag_frequency);
      if (divide_count >= divisor) begin
        divide_count <= '0;
        tck <= ~tck;
      end else begin
        divide_count <= divide_count + 1'b1;
      end
    end
  end
endmodule
