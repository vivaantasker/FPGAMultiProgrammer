`timescale 1ns/1ps

// Vivado/XSim functional coverage harness for programmer_pkg,
// interrupt_controller, and time_multiplex_scheduler.
// Select tb_rtl_coverage as the simulation top to run this independently.
module tb_rtl_coverage;
  import programmer_pkg::*;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;

  // Interrupt controller stimulus and observation.
  logic [15:0] irq_src, irq_enable_cfg, irq_clear_req;
  wire [15:0] irq_status, irq_enable, irq_pending;
  wire irq_active;

  interrupt_controller #(.IRQ_WIDTH(16)) irq_dut (
    .clk, .rst_n, .irq_src, .irq_enable_cfg, .irq_clear_req,
    .irq_status, .irq_enable, .irq_active, .irq_pending
  );

  // Minimal scheduler bus responder. It accepts the first write, then returns
  // an error response, exercising write failure and the abort/fail path.
  logic sched_start;
  wire metadata_mode, metadata_tready, target_fabric_start_en;
  wire [31:0] m_awaddr, m_wdata;
  wire [3:0] m_wstrb;
  wire m_awvalid, m_wvalid, m_bready;
  logic m_awready, m_wready, m_bvalid;
  logic [1:0] m_bresp;
  wire timer_active, timer_irq, finished, failed;
  wire [1:0] phase_index;
  wire [4:0] state_debug;
  wire [31:0] active_flash_offset, active_length_bits, active_duration_ms;
  wire [15:0] irq_clear_req_sched;
  logic memory_busy, memory_done, memory_error, dma_busy, dma_done, dma_error;
  logic jtag_done, jtag_error, jtag_abort_complete, jtag_idcode_ready;
  logic [31:0] jtag_idcode;
  logic [15:0] irq_status_sched;
  logic target_config_status_valid, target_config_success;

  time_multiplex_scheduler #(
    .NUM_IMAGES(3), .CLK_FREQ_HZ(1000), .CYCLES_PER_MS(1), .WATCHDOG_CYCLES(24)
  ) sched_dut (
    .clk, .rst_n, .start(sched_start), .metadata_mode,
    .metadata_tdata(32'b0), .metadata_tvalid(1'b0), .metadata_tready,
    .memory_busy, .memory_done, .memory_error, .dma_busy, .dma_done, .dma_error,
    .jtag_done, .jtag_error, .jtag_abort_complete, .jtag_idcode_ready,
    .jtag_idcode, .irq_status(irq_status_sched), .target_config_status_valid,
    .target_config_success, .target_fabric_start_en,
    .m_awaddr, .m_awvalid, .m_awready, .m_wdata, .m_wstrb, .m_wvalid,
    .m_wready, .m_bresp, .m_bvalid, .m_bready,
    .timer_active, .timer_irq, .finished, .failed, .phase_index, .state_debug,
    .active_flash_offset, .active_length_bits, .active_duration_ms,
    .irq_clear_req(irq_clear_req_sched)
  );

  int checks;
  int pkg_cases;
  int irq_cases;
  int scheduler_cases;

  covergroup pkg_coverage_group with function sample(input int unsigned case_id);
    cp_package_category: coverpoint case_id {
      bins category[] = {[1:12]};
    }
  endgroup
  covergroup irq_coverage_group with function sample(input int unsigned case_id);
    cp_interrupt_scenario: coverpoint case_id {
      bins scenario[] = {[1:12]};
    }
  endgroup
  covergroup scheduler_coverage_group with function sample(input int unsigned case_id);
    cp_scheduler_scenario: coverpoint case_id {
      bins scenario[] = {[1:3]};
    }
  endgroup

  pkg_coverage_group pkg_cov = new();
  irq_coverage_group irq_cov = new();
  scheduler_coverage_group scheduler_cov = new();

  task automatic check(input bit condition, input string message);
    if (!condition) $fatal(1, "[COVERAGE TB FAIL] %s", message);
    checks++;
  endtask

  task automatic tick(input int n = 1);
    repeat (n) @(posedge clk);
    #1;
  endtask

  initial begin : coverage_run
    checks = 0;
    pkg_cases = 0;
    irq_cases = 0;
    scheduler_cases = 0;
    irq_src = '0;
    irq_enable_cfg = '0;
    irq_clear_req = '0;
    sched_start = 1'b0;
    m_awready = 1'b1;
    m_wready = 1'b1;
    m_bvalid = 1'b0;
    m_bresp = 2'b00;
    memory_busy = 1'b0;
    memory_done = 1'b0;
    memory_error = 1'b0;
    dma_busy = 1'b0;
    dma_done = 1'b0;
    dma_error = 1'b0;
    jtag_done = 1'b0;
    jtag_error = 1'b0;
    jtag_abort_complete = 1'b0;
    jtag_idcode_ready = 1'b0;
    jtag_idcode = '0;
    irq_status_sched = '0;
    target_config_status_valid = 1'b0;
    target_config_success = 1'b0;

    repeat (3) tick();
    rst_n = 1'b1;
    tick();
    check(irq_status == 0 && irq_enable == 0 && !irq_active,
          "interrupt reset values");
    check(m_awaddr == 0 && m_wdata == 0 && !finished && !failed,
          "scheduler reset values");
    scheduler_cases++;
    scheduler_cov.sample(1);

    // Package constants, enums, packed records and CRC-16/CCITT-FALSE.
    check(CLK_FREQ_HZ == 100_000_000 && FIFO_DEPTH == 16 && JTAG_MAX_DR_LENGTH == 1024,
          "package parameter values"); pkg_cases++;
    pkg_cov.sample(1);
    check(MEM_SPI == 0 && MEM_QSPI == 1 && MEM_OSPI == 2,
          "all memory type encodings"); pkg_cases += 3;
    pkg_cov.sample(2);
    check(TRIG_MANUAL == 0 && TRIG_GPIO == 1 && TRIG_TIMER == 2 &&
          TRIG_EXTERNAL_TRIGGER == 3 && TRIG_TARGET_FEEDBACK == 4 &&
          TRIG_ERROR_RECOVERY == 5, "all trigger type encodings"); pkg_cases += 6;
    pkg_cov.sample(3);
    check(CMD_CONFIGURE == 8'h01 && CMD_START == 8'h02 && CMD_STATUS == 8'h03 &&
          CMD_ABORT == 8'h04 && CMD_READ_ID == 8'h05 && CMD_RESET == 8'h06 &&
          CMD_READ_ERROR == 8'h07 && CMD_UNKNOWN == 8'hff,
          "all UART command encodings"); pkg_cases += 8;
    pkg_cov.sample(4);
    check(RESP_ACK == 8'h01 && RESP_NACK == 8'h02 && RESP_STATUS == 8'h03 &&
          RESP_PROGRAM_STARTED == 8'h04 && RESP_IDCODE_RECEIVED == 8'h05 &&
          RESP_PROGRAM_COMPLETE == 8'h06 && RESP_PROGRAM_ERROR == 8'h07 &&
          RESP_TIMEOUT == 8'h08 && RESP_UNKNOWN == 8'hff,
          "all UART response encodings"); pkg_cases += 9;
    pkg_cov.sample(5);
    check(ERR_NONE == 0 && ERR_BAD_SOF == 1 && ERR_BAD_EOF == 2 &&
          ERR_INVALID_LENGTH == 3 && ERR_CRC == 4 && ERR_UNKNOWN_CMD == 5 &&
          ERR_INCOMPLETE == 6 && ERR_MEMORY_TIMEOUT == 7 && ERR_MEMORY_ERROR == 8 &&
          ERR_DMA_ERROR == 9 && ERR_JTAG_ERROR == 10 && ERR_IDCODE_MISMATCH == 11 &&
          ERR_ABORTED == 12 && ERR_RESET == 13,
          "all error code encodings"); pkg_cases += 14;
    pkg_cov.sample(6);
    check(IRQ_UART_RX == 0 && IRQ_UART_TX == 1 && IRQ_MEMORY_DONE == 2 &&
          IRQ_MEMORY_ERROR == 3 && IRQ_DMA_DONE == 4 && IRQ_DMA_ERROR == 5 &&
          IRQ_DMA_UNDERRUN == 6 && IRQ_JTAG_DONE == 7 && IRQ_JTAG_ERROR == 8 &&
          IRQ_JTAG_IDCODE_READY == 9 && IRQ_JTAG_RESPONSE_READY == 10 && IRQ_TIMEOUT == 11,
          "all package IRQ index encodings"); pkg_cases += 12;
    pkg_cov.sample(7);
    check(JTAG_CMD_IDCODE == 0 && JTAG_CMD_IR == 1 && JTAG_CMD_DR == 2 &&
          JTAG_CMD_RESET == 3 && JTAG_CMD_XFER == 4,
          "all JTAG command encodings"); pkg_cases += 5;
    pkg_cov.sample(8);
    check(DMA_IDLE == 0 && DMA_RUNNING == 1 && DMA_DONE == 2 && DMA_ERROR == 3 &&
          DMA_ABORTED == 4 && DMA_UNDERRUN == 5,
          "all DMA status encodings"); pkg_cases += 6;
    pkg_cov.sample(9);
    check(CTRL_IDLE == 0 && CTRL_CONFIGURE == 1 && CTRL_MEMORY_CONFIG == 2 &&
          CTRL_DMA_CONFIG == 3 && CTRL_JTAG_CONFIG == 4 && CTRL_START_TRANSFER == 5 &&
          CTRL_WAIT_TRANSFER == 6 && CTRL_VERIFY == 7 && CTRL_REPORT_SUCCESS == 8 &&
          CTRL_ERROR == 9 && CTRL_ABORT == 10 && CTRL_RESET_PERIPHERALS == 11,
          "all controller state encodings"); pkg_cases += 12;
    pkg_cov.sample(10);
    check(TAP_TEST_LOGIC_RESET == 0 && TAP_RUN_TEST_IDLE == 1 && TAP_SELECT_DR_SCAN == 2 &&
          TAP_CAPTURE_DR == 3 && TAP_SHIFT_DR == 4 && TAP_EXIT1_DR == 5 &&
          TAP_PAUSE_DR == 6 && TAP_EXIT2_DR == 7 && TAP_UPDATE_DR == 8 &&
          TAP_SELECT_IR_SCAN == 9 && TAP_CAPTURE_IR == 10 && TAP_SHIFT_IR == 11 &&
          TAP_EXIT1_IR == 12 && TAP_PAUSE_IR == 13 && TAP_EXIT2_IR == 14 &&
          TAP_UPDATE_IR == 15, "all JTAG TAP state encodings"); pkg_cases += 16;
    pkg_cov.sample(11);
    check(crc16_update(16'hffff, 8'h31) == 16'hc782,
          "CRC update reference byte (ASCII '1')"); pkg_cases++;
    pkg_cov.sample(12);
    check(crc16_update(16'hffff, 8'h00) != crc16_update(16'hffff, 8'hff),
          "CRC input sensitivity"); pkg_cases++;
    pkg_cov.sample(12);

    // Interrupt enable is registered. Source edges are latched only when
    // enabled; a held-high source cannot re-latch after clear until it falls.
    irq_enable_cfg = 16'h0001;
    tick();
    check(irq_enable == 16'h0001 && !irq_active, "registered enable, no source"); irq_cases++;
    irq_cov.sample(1);
    irq_src = 16'h0001;
    tick();
    check(irq_status == 16'h0001 && irq_pending == 16'h0001 && irq_active,
          "enabled rising edge sets sticky status"); irq_cases++;
    irq_cov.sample(2);
    tick(3);
    check(irq_status == 16'h0001, "held source does not create repeated events"); irq_cases++;
    irq_cov.sample(3);
    irq_clear_req = 16'h0001;
    tick();
    irq_clear_req = '0;
    check(irq_status == 0 && !irq_active, "clear request clears sticky status"); irq_cases++;
    irq_cov.sample(4);
    tick(2);
    check(irq_status == 0, "held high source does not relatch after clear"); irq_cases++;
    irq_cov.sample(5);
    irq_src = '0;
    tick();
    irq_src = 16'h0001;
    tick();
    check(irq_status == 16'h0001, "new rising edge relatches after low transition"); irq_cases++;
    irq_cov.sample(6);

    // Mask pending without clearing stored status, then enable it and check
    // simultaneous independent sources plus clear/set priority.
    irq_enable_cfg = 16'h0003;
    tick(); // Enable configuration is registered one clock before use.
    irq_src = 16'h0003;
    tick();
    check(irq_status == 16'h0003 && irq_active, "multiple simultaneous IRQ sources"); irq_cases++;
    irq_cov.sample(7);
    irq_enable_cfg = 16'h0002;
    tick();
    check(irq_status == 16'h0003 && irq_pending == 16'h0002 && irq_active,
          "mask changes pending but preserves sticky status"); irq_cases++;
    irq_cov.sample(8);
    irq_clear_req = 16'h0002;
    tick();
    irq_clear_req = '0;
    check(irq_status == 16'h0001 && irq_pending == 0 && !irq_active,
          "clear masked event while other status remains"); irq_cases++;
    irq_cov.sample(9);
    irq_src = '0;
    irq_enable_cfg = 16'hffff;
    tick(); // Register all enables and establish low levels for fresh edges.
    irq_clear_req = 16'h0001;
    irq_src = 16'hffff;
    tick();
    irq_clear_req = '0;
    check(irq_status == 16'hfffe, "clear wins over simultaneous new edge on same bit"); irq_cases++;
    irq_cov.sample(10);
    irq_src = '0;
    tick();
    irq_src = 16'hffff;
    tick();
    check(irq_status == 16'hffff && irq_pending == 16'hffff && irq_active,
          "all IRQ lines enabled and latched"); irq_cases++;
    irq_cov.sample(11);
    irq_clear_req = 16'hffff;
    tick();
    irq_clear_req = '0;
    check(irq_status == 0 && !irq_active, "clear all IRQ lines"); irq_cases++;
    irq_cov.sample(12);

    // Scheduler: first AXI write returns SLVERR. The scheduler must issue its
    // three abort writes, wait for recovery, and end in the sticky FAILED state.
    @(negedge clk) sched_start = 1'b1;
    @(negedge clk) sched_start = 1'b0;
    wait (m_awvalid && m_wvalid);
    tick();
    wait (m_bready);
    @(negedge clk) begin m_bresp = 2'b10; m_bvalid = 1'b1; end
    tick();
    @(negedge clk) begin m_bvalid = 1'b0; m_bresp = 2'b00; end
    // Answer abort writes successfully, irrespective of independent AW/W timing.
    repeat (3) begin
      wait (m_awvalid || m_wvalid);
      wait (m_bready);
      @(negedge clk) m_bvalid = 1'b1;
      tick();
      @(negedge clk) m_bvalid = 1'b0;
    end
    jtag_abort_complete = 1'b1;
    wait (failed || finished);
    check(failed && !finished && !target_fabric_start_en,
          "AXI write error follows abort path to failed"); scheduler_cases++;
    scheduler_cov.sample(2);
    check(!timer_active && phase_index == 0, "failure leaves timer off and phase unchanged"); scheduler_cases++;
    scheduler_cov.sample(3);

    $display("\n========== RTL FUNCTIONAL COVERAGE SUMMARY ==========");
    $display("programmer_pkg: %0d checked bins/cases", pkg_cases);
    $display("interrupt_controller: %0d checked scenarios", irq_cases);
    $display("time_multiplex_scheduler: %0d checked scenarios", scheduler_cases);
    $display("scoreboard checks: %0d", checks);
    $display("=====================================================");
    $finish;
  end

  initial begin
    #200000;
    $fatal(1, "[COVERAGE TB TIMEOUT]");
  end
endmodule
