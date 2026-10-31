`timescale 1ns/1ps

// 16-source sticky, rising-edge interrupt concentrator.
// irq_status stays set until irq_clear_req acknowledges the event.
// Relevant platform assignments: bit 11 task watchdog, bit 12 TARGET_TASK_DONE,
// bit 13 TARGET_TASK_ERROR. Other assignments are documented at the top level.
module interrupt_controller #(
  parameter int IRQ_WIDTH = 16
)(
  input  logic clk,
  input  logic rst_n,
  input  logic [IRQ_WIDTH-1:0] irq_src,
  input  logic [IRQ_WIDTH-1:0] irq_enable_cfg,
  input  logic [IRQ_WIDTH-1:0] irq_clear_req,
  output logic [IRQ_WIDTH-1:0] irq_status,
  output logic [IRQ_WIDTH-1:0] irq_enable,
  output logic irq_active,
  output logic [IRQ_WIDTH-1:0] irq_pending
);
  logic [IRQ_WIDTH-1:0] irq_src_d;
  logic [IRQ_WIDTH-1:0] irq_rise_pulse;

  // Edge detector is used so a level held high cannot continuously re-latch
  // an event immediately after software/scheduler acknowledgement.
  assign irq_rise_pulse = irq_src & ~irq_src_d;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      irq_src_d <= '0;
      irq_enable <= '0;
      irq_status <= '0;
    end else begin
      irq_src_d <= irq_src;
      irq_enable <= irq_enable_cfg;
      irq_status <= (irq_status | (irq_rise_pulse & irq_enable)) & ~irq_clear_req;
    end
  end

  always_comb begin
    irq_pending = irq_status & irq_enable;
    irq_active = |irq_pending;
  end
endmodule
