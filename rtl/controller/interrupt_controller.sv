`timescale 1ns/1ps

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
  // Purpose: central interrupt controller with sticky status bits.
  // Inputs: clk, rst_n, irq_src, irq_enable_cfg, irq_clear_req
  // Outputs: irq_status, irq_enable, irq_active, irq_pending
  // Clock/reset: clk, rst_n
  // Assumption: status bits are sticky until explicitly cleared and can co-exist.

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      irq_status <= '0;
      irq_enable <= '0;
      irq_pending <= '0;
      irq_active <= 1'b0;
    end else begin
      irq_enable <= irq_enable_cfg;
      irq_pending <= irq_src & irq_enable;
      irq_status <= irq_status | (irq_src & irq_enable);

      for (int i = 0; i < IRQ_WIDTH; i++) begin
        if (irq_clear_req[i]) irq_status[i] <= 1'b0;
      end

      irq_active <= |(irq_status & irq_enable);
    end
  end
endmodule
