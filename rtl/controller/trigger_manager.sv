`timescale 1ns/1ps

module trigger_manager #(
  parameter int NUM_TRIGGERS = 6
)(
  input  logic clk,
  input  logic rst_n,
  input  logic manual_trigger,
  input  logic [NUM_TRIGGERS-2:0] gpio_trigger,
  input  logic timer_expired,
  input  logic external_trigger,
  input  logic target_feedback,
  input  logic error_recovery,
  input  logic [2:0] trigger_mode,
  output logic start_event
);
  // Purpose: select and generate a hardware start event from supported trigger sources.
  // Inputs: clk, rst_n, trigger signals, trigger_mode
  // Outputs: start_event
  // Clock/reset: clk, rst_n
  // Assumption: trigger sources are pulsed and converted into a single start pulse.

  logic [NUM_TRIGGERS-1:0] trigger_vec;

  always_comb begin
    trigger_vec[0] = manual_trigger;
    trigger_vec[1] = gpio_trigger[0];
    trigger_vec[2] = timer_expired;
    trigger_vec[3] = external_trigger;
    trigger_vec[4] = target_feedback;
    trigger_vec[5] = error_recovery;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) start_event <= 1'b0;
    else begin
      start_event <= 1'b0;
      if (trigger_vec[trigger_mode]) begin
        start_event <= 1'b1;
      end
    end
  end
endmodule
