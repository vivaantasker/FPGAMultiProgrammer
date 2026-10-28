`timescale 1ns/1ps

module reset_sync #(
  parameter int SYNC_STAGES = 2
)(
  input  logic clk,
  input  logic rst_n,
  output logic rst_sync_n
);
  // Purpose: synchronize asynchronous reset into the main clock domain.
  // Inputs: clk, rst_n
  // Outputs: rst_sync_n
  // Clock/reset: clk, rst_n
  // Assumption: asynchronous reset is active low and will be synchronized.

  logic [SYNC_STAGES-1:0] sync_chain;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sync_chain <= '0;
      rst_sync_n <= 1'b0;
    end else begin
      sync_chain <= {sync_chain[SYNC_STAGES-2:0], 1'b1};
      rst_sync_n <= sync_chain[SYNC_STAGES-1];
    end
  end
endmodule
