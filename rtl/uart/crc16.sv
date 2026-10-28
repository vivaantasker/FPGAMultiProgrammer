`timescale 1ns/1ps

module crc16;
  // Purpose: CRC16 helper used by UART packet validation.
  // Inputs: data, current CRC value via function call
  // Outputs: updated CRC value
  // Clock/reset: none
  // Assumption: CRC-16/ARC polynomial 0x1021 used for packet integrity checks.

  function automatic logic [15:0] crc16_update(input logic [15:0] crc_in, input logic [7:0] data);
    logic [15:0] crc;
    crc = crc_in;
    for (int i = 0; i < 8; i++) begin
      crc = {crc[14:0], 1'b0};
      if ((data[i] ^ crc[15]) == 1'b1) begin
        crc = crc ^ 16'h1021;
      end
    end
    crc16_update = crc;
  endfunction
endmodule
