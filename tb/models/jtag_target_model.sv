`timescale 1ns/1ps

module jtag_target_model (
  input  logic tck,
  input  logic tms,
  input  logic tdi,
  output logic tdo,
  output logic [31:0] idcode
);
  // Purpose: simulate a JTAG target FPGA that responds with an IDCODE.
  // Inputs: tck, tms, tdi
  // Outputs: tdo, idcode
  // Clock/reset: none
  // Assumption: model exposes a simple IDCODE for controller validation only.

  logic [31:0] idcode_reg;
  initial idcode_reg = 32'h1234_5678;

  always_ff @(posedge tck) begin
    if (tms && tdi) begin
      tdo <= 1'b0;
    end else begin
      tdo <= idcode_reg[0];
      idcode_reg <= {idcode_reg[30:0], 1'b0};
    end
  end

  assign idcode = idcode_reg;
endmodule
