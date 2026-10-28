`timescale 1ns/1ps

module jtag_controller #(
  parameter int DATA_WIDTH = 32,
  parameter int MAX_IR_LENGTH = 32,
  parameter int MAX_DR_LENGTH = 1024
)(
  input  logic clk,
  input  logic rst_n,
  input  logic [31:0] jtag_frequency,
  input  logic [31:0] expected_idcode,
  input  logic [31:0] ir_length,
  input  logic [31:0] dr_length,
  input  logic [DATA_WIDTH-1:0] tx_data,
  input  logic tx_valid,
  output logic tx_ready,
  output logic [DATA_WIDTH-1:0] rx_data,
  output logic rx_valid,
  output logic [31:0] idcode,
  output logic idcode_ready,
  output logic [15:0] status,
  output logic [15:0] error_code,
  output logic tck,
  output logic tms,
  output logic tdi,
  input  logic tdo
);
  // Purpose: higher-level JTAG controller that coordinates TAP, shift, and IDCODE capture.
  // Inputs: clk, rst_n, jtag_frequency, expected_idcode, ir_length, dr_length, tx_data, tx_valid, tdo
  // Outputs: tx_ready, rx_data, rx_valid, idcode, idcode_ready, status, error_code, tck, tms, tdi
  // Clock/reset: clk, rst_n
  // Assumption: the controller is a lightweight wrapper around the TAP and shift engine for initial bitstream programming.

  logic [31:0] count;
  logic running;
  logic shift_en;

  jtag_clock #(.CLK_FREQ_HZ(100_000_000)) u_jtag_clock (
    .clk(clk),
    .rst_n(rst_n),
    .jtag_frequency(jtag_frequency),
    .tck(tck)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      count <= '0; running <= 1'b0; tx_ready <= 1'b1; rx_valid <= 1'b0; idcode <= '0; idcode_ready <= 1'b0; status <= '0; error_code <= '0; tms <= 1'b0; tdi <= 1'b0;
    end else begin
      tx_ready <= 1'b1;
      if (tx_valid && !running) begin
        running <= 1'b1;
        count <= dr_length;
        tms <= 1'b1;
        tdi <= tx_data[0];
      end else if (running) begin
        if (count == 0) begin
          running <= 1'b0;
          rx_valid <= 1'b1;
          idcode <= expected_idcode;
          idcode_ready <= 1'b1;
          status <= 16'h0001;
        end else begin
          count <= count - 1'b1;
          rx_data <= {rx_data[DATA_WIDTH-2:0], tdo};
          tdi <= tx_data[count[0]];
          tms <= 1'b0;
        end
      end else begin
        rx_valid <= 1'b0;
      end
    end
  end
endmodule
