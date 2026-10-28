`timescale 1ns/1ps

module jtag_regs #(
  parameter int ADDR_WIDTH = 32,
  parameter int DATA_WIDTH = 32
)(
  input  logic clk,
  input  logic rst_n,
  input  logic [ADDR_WIDTH-1:0] awaddr,
  input  logic awvalid,
  output logic awready,
  input  logic [DATA_WIDTH-1:0] wdata,
  input  logic [DATA_WIDTH/8-1:0] wstrb,
  input  logic wvalid,
  output logic wready,
  output logic [1:0] bresp,
  output logic bvalid,
  input  logic bready,
  input  logic [ADDR_WIDTH-1:0] araddr,
  input  logic arvalid,
  output logic arready,
  output logic [DATA_WIDTH-1:0] rdata,
  output logic [1:0] rresp,
  output logic rvalid,
  input  logic rready,
  output logic [31:0] ir_length,
  output logic [31:0] dr_length,
  output logic [31:0] freq,
  output logic [31:0] expected_idcode,
  output logic [31:0] status,
  output logic [31:0] error_code,
  output logic enable
);
  // Purpose: register map for JTAG mode, frequency, and status.
  // Inputs: clk, rst_n, axi_if
  // Outputs: ir_length, dr_length, freq, expected_idcode, status, error_code, enable
  // Clock/reset: clk, rst_n
  // Assumption: registers are simple control/status words for initial JTAG configuration.

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ir_length <= 32'd32; dr_length <= 32'd32; freq <= 32'd100000; expected_idcode <= '0; status <= '0; error_code <= '0; enable <= 1'b0;
    end else begin
      if (awvalid && awready) begin
        case (awaddr)
          32'h00: ir_length <= wdata;
          32'h04: dr_length <= wdata;
          32'h08: freq <= wdata;
          32'h0C: expected_idcode <= wdata;
          32'h10: enable <= wdata[0];
          default: ;
        endcase
      end
      if (arvalid && arready) begin
        case (araddr)
          32'h00: rdata <= ir_length;
          32'h04: rdata <= dr_length;
          32'h08: rdata <= freq;
          32'h0C: rdata <= expected_idcode;
          32'h10: rdata <= {31'b0, enable};
          default: rdata <= '0;
        endcase
      end
    end
  end

  always_comb begin
    awready = 1'b1; wready = 1'b1; bvalid = awvalid && wvalid; bresp = 2'b00;
    arready = 1'b1; rvalid = arvalid; rresp = 2'b00;
  end
endmodule
