`timescale 1ns/1ps

module fpga_programmer_top #(
  parameter int CLK_FREQ_HZ = programmer_pkg::CLK_FREQ_HZ,
  parameter int AXI_ADDR_WIDTH = programmer_pkg::AXI_ADDR_WIDTH,
  parameter int AXI_DATA_WIDTH = programmer_pkg::AXI_DATA_WIDTH,
  parameter int STREAM_DATA_WIDTH = programmer_pkg::STREAM_DATA_WIDTH,
  parameter int UART_BAUD = programmer_pkg::UART_BAUD
)(
  input  logic clk,
  input  logic rst_n,
  input  logic uart_rx,
  output logic uart_tx,
  output logic [7:0] led,
  input  logic [7:0] gpio_in,
  output logic [7:0] gpio_out,
  input  logic tdo,
  output logic tck,
  output logic tms,
  output logic tdi,
  output logic sclk,
  output logic cs_n,
  output logic mosi,
  input  logic miso,
  output logic qspi_sclk,
  output logic qspi_cs_n,
  inout  wire [3:0] qspi_io,
  output logic ospi_sclk,
  output logic ospi_cs_n,
  inout  wire [7:0] ospi_io
);
  // Purpose: top-level integration for the FPGA programmer RTL.
  // Inputs: clk, rst_n, uart_rx, gpio_in, tdo, miso
  // Outputs: uart_tx, led, gpio_out, JTAG pins, and SPI/QSPI/OSPI flash pins
  // Clock/reset: clk, rst_n
  // Assumption: integration point for UART, core controller, memory, DMA, JTAG, and RAM.

  logic [7:0] command;
  logic [15:0] length;
  logic [7:0] rx_payload [0:255];
  logic [15:0] crc_value;
  logic [7:0] error_code;
  logic packet_valid, packet_error;
  logic response_trigger;
  logic [7:0] response_id;
  logic [7:0] response_payload [0:255];
  logic [7:0] response_len;
  logic [7:0] response_error;
  logic response_busy;
  logic [31:0] idcode;
  logic idcode_ready;
  logic [15:0] status;
  logic [15:0] jtag_error;
  logic [31:0] irq_status;
  logic [31:0] irq_enable;
  logic [31:0] irq_clear;
  logic irq_active;
  logic [2:0] controller_memory_type;
  logic [31:0] controller_memory_address;
  logic [31:0] controller_bitstream_length;
  logic [31:0] controller_expected_idcode;
  logic [31:0] controller_jtag_frequency;
  logic [7:0] controller_jtag_mode;
  logic [2:0] controller_trigger_type;
  logic [15:0] controller_bitstream_id;
  logic [7:0] controller_flags;
  logic controller_start_dma, controller_abort_dma;
  logic controller_start_jtag, controller_abort_jtag;
  logic controller_busy;
  logic [3:0] controller_state;
  logic memory_busy, memory_done, memory_error;
  logic dma_done, dma_error;
  logic s_axi_awvalid, s_axi_awready, s_axi_wvalid, s_axi_wready, s_axi_bvalid, s_axi_bready, s_axi_arvalid, s_axi_arready, s_axi_rvalid, s_axi_rready;
  logic [31:0] s_axi_awaddr, s_axi_wdata, s_axi_araddr, s_axi_rdata;
  logic [3:0] s_axi_wstrb;
  logic [1:0] s_axi_bresp, s_axi_rresp;

  uart_protocol #(.CLK_FREQ_HZ(CLK_FREQ_HZ), .BAUD_RATE(UART_BAUD), .MAX_PAYLOAD(256)) u_uart (
    .clk(clk),
    .rst_n(rst_n),
    .rx(uart_rx),
    .tx(uart_tx),
    .packet_valid(packet_valid),
    .packet_error(packet_error),
    .command(command),
    .length(length),
    .payload(rx_payload),
    .crc_value(crc_value),
    .error_code(error_code),
    .response_trigger(response_trigger),
    .response_id(response_id),
    .response_payload(response_payload),
    .response_len(response_len),
    .response_error(response_error),
    .response_busy(response_busy)
  );

  programmer_controller #(
    .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .STREAM_DATA_WIDTH(STREAM_DATA_WIDTH)
  ) u_controller (
    .clk(clk),
    .rst_n(rst_n),
    .packet_valid(packet_valid),
    .packet_error(packet_error),
    .command(command),
    .length(length),
    .payload(rx_payload),
    .crc_value(crc_value),
    .error_code(error_code),
    .response_trigger(response_trigger),
    .response_id(response_id),
    .response_payload(response_payload),
    .response_len(response_len),
    .response_error(response_error),
    .memory_type(controller_memory_type),
    .memory_address(controller_memory_address),
    .bitstream_length(controller_bitstream_length),
    .expected_idcode(controller_expected_idcode),
    .jtag_frequency(controller_jtag_frequency),
    .jtag_mode(controller_jtag_mode),
    .trigger_type(controller_trigger_type),
    .bitstream_id(controller_bitstream_id),
    .flags(controller_flags),
    .memory_done(memory_done),
    .memory_error(memory_error),
    .dma_done(dma_done),
    .dma_error(dma_error),
    .jtag_done(idcode_ready),
    .jtag_error(|jtag_error),
    .idcode_ready(idcode_ready),
    .idcode_value(idcode),
    .start_dma(controller_start_dma),
    .abort_dma(controller_abort_dma),
    .start_jtag(controller_start_jtag),
    .abort_jtag(controller_abort_jtag),
    .controller_busy(controller_busy),
    .state_out(controller_state)
  );

  memory_manager #(.ADDR_WIDTH(programmer_pkg::MEMORY_ADDRESS_WIDTH), .DATA_WIDTH(STREAM_DATA_WIDTH), .MEM_TYPE_WIDTH(3)) u_mem (
    .clk(clk),
    .rst_n(rst_n),
    .memory_type(controller_memory_type),
    .addr(controller_memory_address[programmer_pkg::MEMORY_ADDRESS_WIDTH-1:0]),
    .length(controller_bitstream_length[15:0]),
    .read_req(controller_start_dma),
    .busy(memory_busy),
    .done(memory_done),
    .error(memory_error),
    .read_data(),
    .sclk(sclk),
    .cs_n(cs_n),
    .mosi(mosi),
    .miso(miso),
    .qspi_sclk(qspi_sclk),
    .qspi_cs_n(qspi_cs_n),
    .qspi_io(qspi_io),
    .ospi_sclk(ospi_sclk),
    .ospi_cs_n(ospi_cs_n),
    .ospi_io(ospi_io)
  );

  jtag_controller #(.DATA_WIDTH(STREAM_DATA_WIDTH), .MAX_IR_LENGTH(programmer_pkg::JTAG_MAX_IR_LENGTH), .MAX_DR_LENGTH(programmer_pkg::JTAG_MAX_DR_LENGTH)) u_jtag (
    .clk(clk),
    .rst_n(rst_n),
    .jtag_frequency(controller_jtag_frequency),
    .expected_idcode(controller_expected_idcode),
    .ir_length(32'd32),
    .dr_length(32'd32),
    .tx_data('0),
    .tx_valid(controller_start_jtag),
    .tx_ready(),
    .rx_data(),
    .rx_valid(),
    .idcode(idcode),
    .idcode_ready(idcode_ready),
    .status(status),
    .error_code(jtag_error),
    .tck(tck),
    .tms(tms),
    .tdi(tdi),
    .tdo(tdo)
  );

  assign led = 8'h00;
  assign gpio_out = 8'h00;
  assign dma_done = 1'b0;
  assign dma_error = 1'b0;
endmodule
