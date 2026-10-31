`timescale 1ns/1ps

// Autonomous multi-image reconfiguration platform.
// The time_multiplex_scheduler is the synthesizable scheduling sequencer and
// AXI4-Lite master. A real RV32 core may replace it at this master interface;
// this top does not claim that the scheduler itself is a RISC-V CPU.
module fpga_multiphase_reconfig_top #(
  parameter int CLK_FREQ_HZ = 100_000_000,
  parameter int AXI_ADDR_WIDTH = 32,
  parameter int AXI_DATA_WIDTH = 32,
  parameter int STREAM_DATA_WIDTH = 32,
  parameter int NUM_IMAGES = 3,
  parameter longint unsigned CYCLES_PER_MS = CLK_FREQ_HZ / 1000,
  parameter int WATCHDOG_CYCLES = 500_000,
  parameter logic [31:0] CFG_IN_OPCODE = 32'h0000_0001,
  parameter logic [31:0] IDCODE_OPCODE = 32'h0000_0009,
  parameter logic [31:0] JTAG_FREQUENCY_HZ = 32'd1_000_000
)(
  input  logic clk,
  input  logic rst_n,
  input  logic schedule_start,
  input  logic [15:0] irq_clear,

  // JTAG target interface. config_status_* should come from the selected
  // FPGA-family adapter (DONE pin/status-register interpretation).
  input  logic target_tdo,
  output logic target_tck,
  output logic target_tms,
  output logic target_tdi,
  input  logic target_config_status_valid,
  input  logic target_config_success,
  // Target task completion/error are asynchronous feedback from the configured
  // FPGA fabric. Hold each level high for >=2 clk cycles (or use a toggle adapter).
  input  logic target_task_done,
  input  logic target_task_error,
  output logic target_fabric_start_en,

  // SPI/QSPI/OSPI flash pins. The scheduler currently selects QSPI.
  output logic spi_sclk,
  output logic spi_cs_n,
  output logic spi_mosi,
  input  logic spi_miso,
  output logic qspi_sclk,
  output logic qspi_cs_n,
  inout  wire [3:0] qspi_io,
  output logic ospi_sclk,
  output logic ospi_cs_n,
  inout  wire [7:0] ospi_io,

  output logic irq,
  output logic [15:0] irq_status,
  // Legacy signal names retained: timer_active tracks target_fabric_start_en;
  // timer_irq pulses only when the maximum-runtime task watchdog expires.
  output logic timer_active,
  output logic timer_irq,
  output logic finished,
  output logic failed,
  output logic [1:0] phase_index,
  output logic [4:0] scheduler_state,
  output logic [31:0] active_flash_offset,
  output logic [31:0] active_length_bits,
  output logic [31:0] active_duration_ms
);
  // AXI4-Lite master to the peripheral control register aperture.
  logic [AXI_ADDR_WIDTH-1:0] awaddr;
  logic awvalid, awready;
  logic [AXI_DATA_WIDTH-1:0] wdata;
  logic [AXI_DATA_WIDTH/8-1:0] wstrb;
  logic wvalid, wready;
  logic [1:0] bresp;
  logic bvalid, bready;
  logic [AXI_ADDR_WIDTH-1:0] araddr;
  logic arvalid, arready;
  logic [AXI_DATA_WIDTH-1:0] rdata;
  logic [1:0] rresp;
  logic rvalid, rready;

  // Register-bank outputs.
  logic [2:0] memory_type;
  logic [31:0] memory_address, memory_length_bits;
  logic memory_start, memory_abort;
  logic [31:0] dma_source_address, dma_length_bits;
  logic dma_start, dma_abort;
  logic [31:0] jtag_ir_length, jtag_ir_opcode, jtag_dr_length;
  logic [31:0] jtag_frequency, jtag_expected_idcode;
  logic [7:0] jtag_mode;
  logic jtag_start, jtag_scan_ir, jtag_capture_idcode, jtag_verify_idcode, jtag_abort;
  logic register_write_error;

  // Memory -> DMA -> JTAG datapath.
  logic memory_busy, memory_done, memory_error;
  logic [STREAM_DATA_WIDTH-1:0] memory_read_data, memory_tdata;
  logic [STREAM_DATA_WIDTH/8-1:0] memory_tkeep;
  logic memory_tvalid, memory_tready, memory_tlast;
  logic dma_sready;
  logic [STREAM_DATA_WIDTH-1:0] dma_tdata;
  logic [STREAM_DATA_WIDTH/8-1:0] dma_tkeep;
  logic dma_tvalid, dma_tready, dma_tlast;
  logic dma_busy, dma_done, dma_error;
  logic jtag_tx_ready, jtag_done, jtag_idcode_ready;
  logic [STREAM_DATA_WIDTH-1:0] jtag_tx_data;
  logic jtag_tx_valid;
  logic [31:0] jtag_idcode;
  logic [15:0] jtag_error_code, jtag_status;
  logic jtag_abort_complete;
  logic [STREAM_DATA_WIDTH-1:0] jtag_rx_data;
  logic jtag_rx_valid;
  logic [$clog2(STREAM_DATA_WIDTH+1)-1:0] jtag_rx_bit_count;

  // Metadata stream bypasses the DMA and is consumed by the scheduler. Once
  // metadata parsing is complete, memory data is routed through DMA normally.
  logic metadata_mode, metadata_tready;
  logic [15:0] scheduler_irq_clear;
  logic [15:0] irq_sources, irq_enable, irq_pending;
  logic [15:0] irq_enable_cfg;
  logic [15:0] irq_clear_combined;
  logic target_task_done_meta, target_task_done_sync;
  logic target_task_error_meta, target_task_error_sync;
  logic target_config_status_valid_meta, target_config_status_valid_sync;
  logic target_config_success_meta, target_config_success_sync;
  logic unused_signals;

  assign memory_tready = metadata_mode ? metadata_tready : dma_sready;
  assign dma_tready = jtag_tx_ready;
  // The JTAG controller consumes a first stream word on the scan_start cycle.
  // IDCODE capture shifts zeros; IR scans shift the programmed opcode; DR image
  // scans consume the actual DMA stream. Do not tie command scans to DMA TVALID.
  assign jtag_tx_valid = dma_tvalid ||
                         (jtag_start && (jtag_scan_ir || jtag_capture_idcode));
  assign jtag_tx_data = jtag_capture_idcode ? '0 :
                        jtag_scan_ir ? jtag_ir_opcode[STREAM_DATA_WIDTH-1:0] :
                        dma_tdata;
  assign araddr = '0;
  assign arvalid = 1'b0;
  assign rready = 1'b1;
  assign irq_enable_cfg = 16'hFFFF;
  assign irq_clear_combined = scheduler_irq_clear | irq_clear;

  // Two-flop synchronization for target-originated event pins.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      target_task_done_meta <= 1'b0;
      target_task_done_sync <= 1'b0;
      target_task_error_meta <= 1'b0;
      target_task_error_sync <= 1'b0;
      target_config_status_valid_meta <= 1'b0;
      target_config_status_valid_sync <= 1'b0;
      target_config_success_meta <= 1'b0;
      target_config_success_sync <= 1'b0;
    end else begin
      target_task_done_meta <= target_task_done;
      target_task_done_sync <= target_task_done_meta;
      target_task_error_meta <= target_task_error;
      target_task_error_sync <= target_task_error_meta;
      target_config_status_valid_meta <= target_config_status_valid;
      target_config_status_valid_sync <= target_config_status_valid_meta;
      target_config_success_meta <= target_config_success;
      target_config_success_sync <= target_config_success_meta;
    end
  end
  assign unused_signals = ^{spi_miso, ospi_io, jtag_mode, jtag_status,
                            jtag_abort_complete, jtag_rx_data, jtag_rx_valid,
                            jtag_rx_bit_count, memory_read_data, memory_tkeep,
                            dma_tkeep, dma_tlast};

  time_multiplex_scheduler #(
    .ADDR_WIDTH(AXI_ADDR_WIDTH), .DATA_WIDTH(AXI_DATA_WIDTH),
    .NUM_IMAGES(NUM_IMAGES), .CLK_FREQ_HZ(CLK_FREQ_HZ),
    .CYCLES_PER_MS(CYCLES_PER_MS), .WATCHDOG_CYCLES(WATCHDOG_CYCLES),
    .CFG_IN_OPCODE(CFG_IN_OPCODE), .IDCODE_OPCODE(IDCODE_OPCODE),
    .JTAG_FREQUENCY_HZ(JTAG_FREQUENCY_HZ)
  ) u_scheduler (
    .clk(clk), .rst_n(rst_n), .start(schedule_start),
    .metadata_mode(metadata_mode), .metadata_tdata(memory_tdata),
    .metadata_tvalid(memory_tvalid), .metadata_tready(metadata_tready),
    .memory_busy(memory_busy), .memory_done(memory_done), .memory_error(memory_error),
    .dma_busy(dma_busy), .dma_done(dma_done), .dma_error(dma_error),
    .jtag_done(jtag_done), .jtag_error((|jtag_error_code) || register_write_error),
    .jtag_abort_complete(jtag_abort_complete),
    .jtag_idcode_ready(jtag_idcode_ready), .jtag_idcode(jtag_idcode),
    .irq_status(irq_status),
    .target_config_status_valid(target_config_status_valid_sync),
    .target_config_success(target_config_success_sync),
    .target_fabric_start_en(target_fabric_start_en),
    .m_awaddr(awaddr), .m_awvalid(awvalid), .m_awready(awready),
    .m_wdata(wdata), .m_wstrb(wstrb), .m_wvalid(wvalid), .m_wready(wready),
    .m_bresp(bresp), .m_bvalid(bvalid), .m_bready(bready),
    .timer_active(timer_active), .timer_irq(timer_irq),
    .finished(finished), .failed(failed), .phase_index(phase_index),
    .state_debug(scheduler_state), .active_flash_offset(active_flash_offset),
    .active_length_bits(active_length_bits), .active_duration_ms(active_duration_ms),
    .irq_clear_req(scheduler_irq_clear)
  );

  programmer_control_regs_axi #(
    .ADDR_WIDTH(AXI_ADDR_WIDTH), .DATA_WIDTH(AXI_DATA_WIDTH)
  ) u_control_regs (
    .clk(clk), .rst_n(rst_n),
    .s_awaddr(awaddr), .s_awvalid(awvalid), .s_awready(awready),
    .s_wdata(wdata), .s_wstrb(wstrb), .s_wvalid(wvalid), .s_wready(wready),
    .s_bresp(bresp), .s_bvalid(bvalid), .s_bready(bready),
    .s_araddr(araddr), .s_arvalid(arvalid), .s_arready(arready),
    .s_rdata(rdata), .s_rresp(rresp), .s_rvalid(rvalid), .s_rready(rready),
    .memory_type(memory_type), .memory_address(memory_address),
    .memory_length_bits(memory_length_bits), .memory_start(memory_start),
    .memory_abort(memory_abort), .memory_busy(memory_busy),
    .memory_done(memory_done), .memory_error(memory_error),
    .dma_source_address(dma_source_address), .dma_length_bits(dma_length_bits),
    .dma_start(dma_start), .dma_abort(dma_abort), .dma_busy(dma_busy),
    .dma_done(dma_done), .dma_error(dma_error),
    .jtag_ir_length(jtag_ir_length), .jtag_ir_opcode(jtag_ir_opcode),
    .jtag_dr_length(jtag_dr_length), .jtag_frequency(jtag_frequency),
    .jtag_expected_idcode(jtag_expected_idcode), .jtag_mode(jtag_mode),
    .jtag_start(jtag_start), .jtag_scan_ir(jtag_scan_ir),
    .jtag_capture_idcode(jtag_capture_idcode), .jtag_verify_idcode(jtag_verify_idcode),
    .jtag_abort(jtag_abort), .jtag_done(jtag_done),
    .jtag_error(|jtag_error_code), .jtag_idcode(jtag_idcode),
    .write_access_error(register_write_error)
  );

  memory_manager #(
    .ADDR_WIDTH(programmer_pkg::MEMORY_ADDRESS_WIDTH),
    .DATA_WIDTH(STREAM_DATA_WIDTH), .MEM_TYPE_WIDTH(3),
    .CLK_FREQ_HZ(CLK_FREQ_HZ)
  ) u_memory_manager (
    .clk(clk), .rst_n(rst_n), .memory_type(memory_type),
    .addr(memory_address[programmer_pkg::MEMORY_ADDRESS_WIDTH-1:0]),
    .length(memory_length_bits), .read_req(memory_start), .abort(memory_abort),
    .busy(memory_busy), .done(memory_done), .error(memory_error),
    .read_data(memory_read_data), .m_axis_tdata(memory_tdata),
    .m_axis_tkeep(memory_tkeep), .m_axis_tvalid(memory_tvalid),
    .m_axis_tready(memory_tready), .m_axis_tlast(memory_tlast),
    .sclk(spi_sclk), .cs_n(spi_cs_n), .mosi(spi_mosi), .miso(spi_miso),
    .qspi_sclk(qspi_sclk), .qspi_cs_n(qspi_cs_n), .qspi_io(qspi_io),
    .ospi_sclk(ospi_sclk), .ospi_cs_n(ospi_cs_n), .ospi_io(ospi_io)
  );

  dma_controller #(.DATA_WIDTH(STREAM_DATA_WIDTH)) u_dma (
    .clk(clk), .rst_n(rst_n), .start(dma_start), .abort(dma_abort),
    .source_address(dma_source_address), .transfer_length(dma_length_bits),
    .s_axis_tdata(memory_tdata), .s_axis_tkeep(memory_tkeep),
    .s_axis_tvalid(memory_tvalid), .s_axis_tready(dma_sready),
    .s_axis_tlast(memory_tlast), .m_axis_tdata(dma_tdata),
    .m_axis_tkeep(dma_tkeep), .m_axis_tvalid(dma_tvalid),
    .m_axis_tready(dma_tready), .m_axis_tlast(dma_tlast),
    .done(dma_done), .error(dma_error), .busy(dma_busy)
  );

  jtag_controller #(
    .DATA_WIDTH(STREAM_DATA_WIDTH),
    .MAX_IR_LENGTH(programmer_pkg::JTAG_MAX_IR_LENGTH),
    .MAX_DR_LENGTH(32'hFFFF_FFFF), .CLK_FREQ_HZ(CLK_FREQ_HZ)
  ) u_jtag (
    .clk(clk), .rst_n(rst_n), .jtag_frequency(jtag_frequency),
    .expected_idcode(jtag_expected_idcode), .ir_length(jtag_ir_length),
    .dr_length(jtag_dr_length), .tx_data(jtag_tx_data),
    .tx_valid(jtag_tx_valid), .tx_ready(jtag_tx_ready),
    .rx_data(jtag_rx_data), .rx_valid(jtag_rx_valid),
    .rx_bit_count(jtag_rx_bit_count), .done(jtag_done),
    .idcode(jtag_idcode), .idcode_ready(jtag_idcode_ready),
    .abort_complete(jtag_abort_complete), .status(jtag_status),
    .error_code(jtag_error_code), .tck(target_tck), .tms(target_tms),
    .tdi(target_tdi), .tdo(target_tdo), .scan_start(jtag_start),
    .scan_ir(jtag_scan_ir), .capture_idcode(jtag_capture_idcode),
    .verify_idcode(jtag_verify_idcode), .abort(jtag_abort)
  );

  always_comb begin
    irq_sources = '0;
    irq_sources[2]  = memory_done;
    irq_sources[3]  = memory_error;
    irq_sources[4]  = dma_done;
    irq_sources[5]  = dma_error;
    irq_sources[7]  = jtag_done;
    irq_sources[8]  = (|jtag_error_code) || register_write_error;
    irq_sources[9]  = jtag_idcode_ready;
    irq_sources[11] = timer_irq; // target-runtime watchdog expiry
    irq_sources[12] = target_task_done_sync;
    irq_sources[13] = target_task_error_sync;
  end

  interrupt_controller #(.IRQ_WIDTH(16)) u_irq_controller (
    .clk(clk), .rst_n(rst_n), .irq_src(irq_sources),
    .irq_enable_cfg(irq_enable_cfg), .irq_clear_req(irq_clear_combined),
    .irq_status(irq_status), .irq_enable(irq_enable),
    .irq_active(irq), .irq_pending(irq_pending)
  );
endmodule
