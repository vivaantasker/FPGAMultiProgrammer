`timescale 1ns/1ps

module tb_programmer_controller;
  logic clk = 0;
  logic rst_n = 0;
  logic packet_valid = 0;
  logic packet_error = 0;
  logic [7:0] command = 0;
  logic [15:0] length = 0;
  logic [7:0] payload [0:255];
  logic [15:0] crc_value = 0;
  logic [7:0] error_code = 0;
  logic response_trigger;
  logic [7:0] response_id;
  logic [7:0] response_payload [0:255];
  logic [7:0] response_len;
  logic [7:0] response_error;
  logic [2:0] memory_type;
  logic [31:0] memory_address;
  logic [31:0] bitstream_length;
  logic [31:0] expected_idcode;
  logic [31:0] jtag_frequency;
  logic [7:0] jtag_mode;
  logic [2:0] trigger_type;
  logic [15:0] bitstream_id;
  logic [7:0] flags;
  logic memory_done = 0;
  logic memory_error = 0;
  logic dma_done = 0;
  logic dma_error = 0;
  logic jtag_done = 0;
  logic jtag_error = 0;
  logic idcode_ready = 0;
  logic [31:0] idcode_value = 0;
  logic start_dma, abort_dma, start_jtag, abort_jtag, controller_busy;
  logic [3:0] state_out;

  programmer_controller #(.AXI_ADDR_WIDTH(32), .AXI_DATA_WIDTH(32), .STREAM_DATA_WIDTH(32)) dut (
    .clk(clk),
    .rst_n(rst_n),
    .packet_valid(packet_valid),
    .packet_error(packet_error),
    .command(command),
    .length(length),
    .payload(payload),
    .crc_value(crc_value),
    .error_code(error_code),
    .response_trigger(response_trigger),
    .response_id(response_id),
    .response_payload(response_payload),
    .response_len(response_len),
    .response_error(response_error),
    .memory_type(memory_type),
    .memory_address(memory_address),
    .bitstream_length(bitstream_length),
    .expected_idcode(expected_idcode),
    .jtag_frequency(jtag_frequency),
    .jtag_mode(jtag_mode),
    .trigger_type(trigger_type),
    .bitstream_id(bitstream_id),
    .flags(flags),
    .memory_done(memory_done),
    .memory_error(memory_error),
    .dma_done(dma_done),
    .dma_error(dma_error),
    .jtag_done(jtag_done),
    .jtag_error(jtag_error),
    .idcode_ready(idcode_ready),
    .idcode_value(idcode_value),
    .start_dma(start_dma),
    .abort_dma(abort_dma),
    .start_jtag(start_jtag),
    .abort_jtag(abort_jtag),
    .controller_busy(controller_busy),
    .state_out(state_out)
  );

  always #5 clk = ~clk;

  initial begin
    #20 rst_n = 1;
    #20 packet_valid = 1; command = 8'h01; payload[0] = 8'd0; payload[1] = 8'd0; payload[2] = 8'd0; payload[3] = 8'd0; payload[4] = 8'd0;
    payload[5] = 8'd4; payload[6] = 8'd0; payload[7] = 8'd0; payload[8] = 8'd0;
    payload[9] = 8'd0; payload[10] = 8'd0; payload[11] = 8'd0; payload[12] = 8'd0;
    payload[13] = 8'd0; payload[14] = 8'd0; payload[15] = 8'd0; payload[16] = 8'd0;
    payload[17] = 8'd0; payload[18] = 8'd0; payload[19] = 8'd0; payload[20] = 8'd0; payload[21] = 8'd0;
    #20 packet_valid = 0; memory_done = 1; #20 memory_done = 0; dma_done = 1; #20 dma_done = 0; idcode_ready = 1; idcode_value = 32'h12345678; #20 idcode_ready = 0;
    #200 $finish;
  end
endmodule
