`timescale 1ns/1ps

// Integrated event-driven multi-image testbench.
// Flow: QSPI metadata -> AXI-Lite setup -> IDCODE -> CFG_IN IR ->
// QSPI image -> DMA AXI-Stream -> JTAG DR -> target config status ->
// target task runs for a variable time -> TARGET_TASK_DONE IRQ -> next image.
module tb_multi_image_schedule;
  localparam int CLK_HZ = 10_000_000;
  localparam int TASK_WATCHDOG_MS = 100;
  localparam logic [31:0] TARGET_IDCODE = 32'h1234_5678;
  localparam time TASK_A_TIME = 45_000ns;
  localparam time TASK_B_TIME = 120_000ns;
  localparam time TASK_C_TIME = 15_000ns;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic schedule_start = 1'b0;
  logic [15:0] irq_clear = '0;
  logic target_tck, target_tms, target_tdi;
  wire target_tdo;
  logic target_config_status_valid = 1'b0;
  logic target_config_success = 1'b1;
  logic target_task_done = 1'b0;
  logic target_task_error = 1'b0;
  logic target_fabric_start_en;
  logic spi_sclk, spi_cs_n, spi_mosi;
  logic qspi_sclk, qspi_cs_n;
  tri [3:0] qspi_io;
  logic ospi_sclk, ospi_cs_n;
  tri [7:0] ospi_io;
  logic irq, timer_active, timer_irq, finished, failed;
  logic [15:0] irq_status;
  logic [1:0] phase_index;
  logic [4:0] scheduler_state;
  logic [31:0] active_flash_offset, active_length_bits, active_duration_ms;

  logic [7:0] expected_bytes [0:2][0:8];
  logic [31:0] expected_words [0:2][0:2];
  integer mem_beats [0:2];
  integer dma_beats [0:2];
  integer jtag_bits [0:2];
  integer metadata_beats = 0;
  integer jtag_done_count = 0;
  integer target_status_accept_count = 0;
  integer target_task_count = 0;
  integer axi_write_count = 0;
  integer target_status_delay = -1;
  logic dr_scan_pending = 1'b0;
  logic idcode_ir_pending = 1'b0;
  logic cfg_in_ir_pending = 1'b0;
  time task_start_time [0:2];
  time task_runtime [0:2];
  integer i;

  // First-failure history. The normal test reports only the final scheduler
  // state; that may already be an abort-write state. Sample the prior cycle so
  // the failure report identifies the state/sequence that first raised failed.
  logic [4:0] sampled_state = '0;
  logic [3:0] sampled_sequence = '0;
  logic [3:0] sampled_sequence_index = '0;
  logic [31:0] sampled_write_address = '0;
  logic [31:0] sampled_write_data = '0;
  logic sampled_wr_done = 1'b0;
  logic sampled_wr_error = 1'b0;
  logic sampled_memory_error = 1'b0;
  logic sampled_dma_error = 1'b0;
  logic [15:0] sampled_jtag_error = '0;
  logic [4:0] first_failure_state = '0;
  logic [3:0] first_failure_sequence = '0;
  logic [3:0] first_failure_sequence_index = '0;
  logic [31:0] first_failure_write_address = '0;
  logic [31:0] first_failure_write_data = '0;
  logic first_failure_wr_done = 1'b0;
  logic first_failure_wr_error = 1'b0;
  logic first_failure_memory_error = 1'b0;
  logic first_failure_dma_error = 1'b0;
  logic [15:0] first_failure_jtag_error = '0;
  logic first_failure_captured = 1'b0;

  // Human-readable trace: one integrated testbench, with milestone labels that
  // tell us which pipeline stage is active without opening every module's TB.
  logic [4:0] trace_last_state = 5'h1F;
  logic [1:0] trace_last_phase = 2'h0;

  function automatic string state_name(input logic [4:0] value);
    case (value)
      5'd0:  state_name = "IDLE";
      5'd1:  state_name = "ISSUE_AXI_WRITE";
      5'd2:  state_name = "WAIT_AXI_WRITE";
      5'd3:  state_name = "WAIT_FLASH_METADATA";
      5'd4:  state_name = "WAIT_IDCODE_DR";
      5'd5:  state_name = "WAIT_CFG_IN_IR";
      5'd6:  state_name = "WAIT_FLASH_DMA_JTAG";
      5'd7:  state_name = "WAIT_TARGET_CONFIG_STATUS";
      5'd8:  state_name = "TARGET_RUNNING";
      5'd9:  state_name = "ABORTING";
      5'd10: state_name = "DONE";
      5'd11: state_name = "FAILED";
      5'd12: state_name = "WAIT_IDCODE_IR";
      5'd13: state_name = "WAIT_ABORT_RECOVERY";
      5'd14: state_name = "RELEASE_TARGET";
      default: state_name = "UNKNOWN_STATE";
    endcase
  endfunction

  function automatic string sequence_name(input logic [3:0] value);
    case (value)
      4'd0: sequence_name = "METADATA_CONFIG";
      4'd1: sequence_name = "METADATA_READ_START";
      4'd2: sequence_name = "IMAGE_REGISTER_CONFIG";
      4'd3: sequence_name = "IDCODE_IR";
      4'd4: sequence_name = "IDCODE_DR";
      4'd5: sequence_name = "CFG_IN_OPCODE";
      4'd6: sequence_name = "CFG_IN_IR";
      4'd7: sequence_name = "IMAGE_TRANSFER";
      4'd8: sequence_name = "ABORT";
      default: sequence_name = "UNKNOWN_SEQUENCE";
    endcase
  endfunction

  always #50 clk = ~clk; // 10 MHz system clock.

  always @(negedge clk) begin
    if (rst_n) begin
      sampled_state = scheduler_state;
      sampled_sequence = dut.u_scheduler.sequence_kind;
      sampled_sequence_index = dut.u_scheduler.sequence_index;
      sampled_write_address = dut.u_scheduler.wr_req_addr;
      sampled_write_data = dut.u_scheduler.wr_req_data;
      sampled_wr_done = dut.u_scheduler.wr_done;
      sampled_wr_error = dut.u_scheduler.wr_error;
      sampled_memory_error = dut.memory_error;
      sampled_dma_error = dut.dma_error;
      sampled_jtag_error = dut.jtag_error_code;
    end
  end
  
 
always @(posedge failed) begin
    if (!first_failure_captured) begin
        first_failure_captured = 1'b1;

        // Capture the previous-cycle state and transaction.
        first_failure_state         = sampled_state;
        first_failure_sequence      = sampled_sequence;
        first_failure_sequence_index = sampled_sequence_index;
        first_failure_write_address = sampled_write_address;
        first_failure_write_data    = sampled_write_data;
        first_failure_wr_done       = sampled_wr_done;
        first_failure_wr_error      = sampled_wr_error;
        first_failure_memory_error  = sampled_memory_error;
        first_failure_dma_error     = sampled_dma_error;
        first_failure_jtag_error    = sampled_jtag_error;

        $display("\n========== FIRST FAILURE ==========");
        $display("Time       : %0t", $time);
        $display("State      : %s (%0d)",
                 state_name(first_failure_state), first_failure_state);
        $display("Sequence   : %s (%0d)",
                 sequence_name(first_failure_sequence),
                 first_failure_sequence);
        $display("Index      : %0d", first_failure_sequence_index);

        $display("AXI address: %08h",
                 first_failure_write_address);
        $display("AXI data   : %08h",
                 first_failure_write_data);
        $display("AXI done/error: %b/%b",
                 first_failure_wr_done, first_failure_wr_error);

        $display("Memory error: %b", first_failure_memory_error);
        $display("DMA error   : %b", first_failure_dma_error);
        $display("JTAG error  : %04h", first_failure_jtag_error);

        $display("Metadata count: %0d",
                 dut.u_scheduler.metadata_word_count);
        $display("Metadata valid: %b",
                 dut.u_scheduler.metadata_valid);

        // Print all 12 words captured from QSPI.
        for (int k = 0; k < 12; k++) begin
            $display("[METADATA] word[%0d] = 0x%08h",
                     k, dut.u_scheduler.metadata_words[k]);
        end

        // Decode the three metadata entries.
        for (int img = 0; img < 3; img++) begin
            $display(
                "[IMAGE %0d] offset=%08h length=%08h idcode=%08h duration=%08h",
                img,
                dut.u_scheduler.metadata_words[img*4],
                dut.u_scheduler.metadata_words[img*4+1],
                dut.u_scheduler.metadata_words[img*4+2],
                dut.u_scheduler.metadata_words[img*4+3]
            );
        end

        $display("===================================\n");
    end
end


  // Print only scheduler transitions and phase changes. This keeps the console
  // readable while giving a direct view of the end-to-end transaction order.
  always @(negedge clk) begin
    if (rst_n) begin
      if (scheduler_state !== trace_last_state) begin
        $display("[FLOW %0t] image=%0d state=%s seq=%s idx=%0d",
          $time, phase_index, state_name(scheduler_state),
          sequence_name(dut.u_scheduler.sequence_kind),
          dut.u_scheduler.sequence_index);
        trace_last_state = scheduler_state;
      end
      if (phase_index !== trace_last_phase) begin
        $display("[IMAGE %0t] scheduler advanced to image %0d (flash=0x%06h, bits=%0d)",
          $time, phase_index, active_flash_offset[23:0], active_length_bits);
        trace_last_phase = phase_index;
      end
    end
  end

  fpga_multiphase_reconfig_top #(
    .CLK_FREQ_HZ(CLK_HZ), .NUM_IMAGES(3),
    .CYCLES_PER_MS(CLK_HZ/1000), .WATCHDOG_CYCLES(100_000),
    .CFG_IN_OPCODE(32'h1), .IDCODE_OPCODE(32'h9),
    .JTAG_FREQUENCY_HZ(32'd1_000_000)
  ) dut (
    .clk(clk), .rst_n(rst_n), .schedule_start(schedule_start), .irq_clear(irq_clear),
    .target_tdo(target_tdo), .target_tck(target_tck),
    .target_tms(target_tms), .target_tdi(target_tdi),
    .target_config_status_valid(target_config_status_valid),
    .target_config_success(target_config_success),
    .target_task_done(target_task_done), .target_task_error(target_task_error),
    .target_fabric_start_en(target_fabric_start_en),
    .spi_sclk(spi_sclk), .spi_cs_n(spi_cs_n), .spi_mosi(spi_mosi), .spi_miso(1'b0),
    .qspi_sclk(qspi_sclk), .qspi_cs_n(qspi_cs_n), .qspi_io(qspi_io),
    .ospi_sclk(ospi_sclk), .ospi_cs_n(ospi_cs_n), .ospi_io(ospi_io),
    .irq(irq), .irq_status(irq_status), .timer_active(timer_active),
    .timer_irq(timer_irq), .finished(finished), .failed(failed),
    .phase_index(phase_index), .scheduler_state(scheduler_state),
    .active_flash_offset(active_flash_offset), .active_length_bits(active_length_bits),
    .active_duration_ms(active_duration_ms)
  );

  jtag_target_model #(
    .IR_LENGTH(4), .IDCODE_INSTRUCTION(4'h9), .IDCODE_VALUE(TARGET_IDCODE)
  ) u_target (
    .rst_n(rst_n), .tck(target_tck), .tms(target_tms), .tdi(target_tdi),
    .tdo(target_tdo), .idcode()
  );

  qspi_nor_multi_image_model #(.FLASH_BYTES(262144), .DUMMY_CYCLES(2)) u_flash (
    .cs_n(qspi_cs_n), .sclk(qspi_sclk), .io(qspi_io)
  );

  task automatic check_stream_word(
    input integer image,
    input integer beat,
    input logic [31:0] data,
    input logic [3:0] keep,
    input logic last,
    input string stage
  );
    logic [3:0] expected_keep;
    logic expected_last;
    begin
      expected_keep = (beat == 2) ? 4'b0001 : 4'b1111;
      expected_last = (beat == 2);
      if (data !== expected_words[image][beat] || keep !== expected_keep || last !== expected_last)
        $fatal(1, "%s image=%0d beat=%0d data=%08x expected=%08x keep=%x/%x last=%b/%b",
          stage, image, beat, data, expected_words[image][beat], keep, expected_keep,
          last, expected_last);
    end
  endtask

  // Model target DONE/status. It is asserted only after the complete image DR
  // scan has finished; the scheduler must not enable the fabric before this.
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      target_config_status_valid <= 1'b0;
      target_status_delay <= -1;
      dr_scan_pending <= 1'b0;
      idcode_ir_pending <= 1'b0;
      cfg_in_ir_pending <= 1'b0;
      target_status_accept_count <= 0;
    end else begin
      if (dut.jtag_start && dut.jtag_scan_ir && !dut.jtag_capture_idcode) begin
        if (dut.u_scheduler.sequence_kind == 4'd3)
          idcode_ir_pending <= 1'b1;
        else if (dut.u_scheduler.sequence_kind == 4'd6)
          cfg_in_ir_pending <= 1'b1;
      end

      // Check the target instruction after the corresponding IR scan has
      // actually completed and the target has committed Update-IR.
      if (dut.jtag_done && idcode_ir_pending) begin
        if (u_target.active_instruction !== 4'h9)
          $fatal(1, "IDCODE IR scan failed: target instruction=%h expected=9",
            u_target.active_instruction);
        idcode_ir_pending <= 1'b0;
      end
      if (dut.jtag_done && cfg_in_ir_pending) begin
        if (u_target.active_instruction !== 4'h1)
          $fatal(1, "CFG_IN IR scan failed: target instruction=%h expected=1",
            u_target.active_instruction);
        cfg_in_ir_pending <= 1'b0;
      end

      if (dut.jtag_start && !dut.jtag_scan_ir && !dut.jtag_capture_idcode) begin
        if (u_target.active_instruction !== 4'h1)
          $fatal(1, "CFG_IN instruction was not active at image DR start: %h",
            u_target.active_instruction);
        dr_scan_pending <= 1'b1;
      end

      if (dut.jtag_done && dr_scan_pending) begin
        dr_scan_pending <= 1'b0;
        target_status_delay <= 5;
      end else if (target_status_delay > 0) begin
        target_status_delay <= target_status_delay - 1;
      end else if (target_status_delay == 0) begin
        target_config_status_valid <= 1'b1;
        target_status_delay <= -1;
      end

      if (target_config_status_valid && scheduler_state == 5'd7) begin
        if (u_target.tap_state !== programmer_pkg::TAP_RUN_TEST_IDLE)
          $fatal(1, "Target config status asserted before JTAG returned to Run-Test/Idle");
        target_config_status_valid <= 1'b0;
        target_status_accept_count <= target_status_accept_count + 1;
      end
    end
  end

  // Scoreboard: metadata, memory-to-DMA beats, DMA-to-JTAG beats, AXI-Lite
  // register writes, and JTAG completion handshakes.
  always @(posedge clk) begin
    if (rst_n) begin
      if (dut.awvalid && dut.awready) axi_write_count <= axi_write_count + 1;

      if (dut.metadata_mode && dut.memory_tvalid && dut.memory_tready) begin
        if (metadata_beats >= 12) $fatal(1, "More than 12 metadata words were received");
        metadata_beats <= metadata_beats + 1;
      end else if (!dut.metadata_mode && dut.memory_tvalid && dut.memory_tready) begin
        if (mem_beats[phase_index] >= 3) $fatal(1, "Extra memory stream beat in image %0d", phase_index);
        check_stream_word(phase_index, mem_beats[phase_index], dut.memory_tdata,
                          dut.memory_tkeep, dut.memory_tlast, "MEMORY");
        mem_beats[phase_index] <= mem_beats[phase_index] + 1;
      end

      if (dut.dma_tvalid && dut.dma_tready) begin
        if (dma_beats[phase_index] >= 3) $fatal(1, "Extra DMA stream beat in image %0d", phase_index);
        check_stream_word(phase_index, dma_beats[phase_index], dut.dma_tdata,
                          dut.dma_tkeep, dut.dma_tlast, "DMA");
        dma_beats[phase_index] <= dma_beats[phase_index] + 1;
      end

      if (dut.jtag_done) jtag_done_count <= jtag_done_count + 1;
      if (dut.jtag_idcode_ready && dut.jtag_idcode !== TARGET_IDCODE)
        $fatal(1, "IDCODE mismatch: captured=%08h expected=%08h",
          dut.jtag_idcode, TARGET_IDCODE);
      if (timer_irq) $fatal(1, "Runtime watchdog expired unexpectedly");
      if (timer_active !== target_fabric_start_en)
        $fatal(1, "Legacy timer_active indicator must track target fabric enable");
      if (target_fabric_start_en && (target_status_accept_count <= phase_index))
        $fatal(1, "Target fabric enabled before a successful configuration-status handshake");
    end
  end

  // Sample the target input on the JTAG TCK rising edge, exactly when the
  // target TAP consumes TDI. The target's pre-edge TAP state identifies an
  // active DR shift; IDCODE capture DR and all IR scans are excluded.
  always @(posedge target_tck) begin
    if (rst_n && (u_target.tap_state == programmer_pkg::TAP_SHIFT_DR) &&
        !dut.u_jtag.active_scan_ir && !dut.u_jtag.active_capture_idcode) begin
      if (jtag_bits[phase_index] >= 72)
        $fatal(1, "More than 72 image bits shifted for phase %0d", phase_index);
      if (target_tdi !== expected_bytes[phase_index][jtag_bits[phase_index]/8]
                                           [jtag_bits[phase_index]%8])
        $fatal(1, "JTAG TDI mismatch phase=%0d bit=%0d expected=%b actual=%b",
          phase_index, jtag_bits[phase_index],
          expected_bytes[phase_index][jtag_bits[phase_index]/8]
                                     [jtag_bits[phase_index]%8], target_tdi);
      jtag_bits[phase_index] = jtag_bits[phase_index] + 1;
    end
  end

  // Behavioral FPGA fabric: each newly configured image completes at a
  // different time (45 us, 120 us, 15 us). TARGET_TASK_DONE is held until the
  // scheduler quiesces the fabric, providing an explicit event handshake.
  initial begin : target_fabric_model
    wait (rst_n === 1'b1);
    for (int image = 0; image < 3; image++) begin
      wait (target_fabric_start_en === 1'b1);
      if (phase_index != image[1:0])
        $fatal(1, "Wrong image enabled: expected %0d, got %0d", image, phase_index);
      task_start_time[image] = $time;
      case (image)
        0: #(TASK_A_TIME);
        1: #(TASK_B_TIME);
        2: #(TASK_C_TIME);
      endcase
      if (!target_fabric_start_en)
        $fatal(1, "Scheduler switched image %0d before its TASK_DONE event", image);
      if (phase_index != image[1:0])
        $fatal(1, "Phase index changed before TASK_DONE for image %0d", image);
      task_runtime[image] = $time - task_start_time[image];
      @(negedge clk);
      target_task_done = 1'b1;
      target_task_count = target_task_count + 1;
      wait (target_fabric_start_en === 1'b0);
      repeat (2) @(negedge clk);
      target_task_done = 1'b0;
    end
  end

  initial begin : initialize_and_run
    expected_bytes[0][0]=8'h11; expected_bytes[0][1]=8'h22; expected_bytes[0][2]=8'h33;
    expected_bytes[0][3]=8'h44; expected_bytes[0][4]=8'h55; expected_bytes[0][5]=8'h66;
    expected_bytes[0][6]=8'h77; expected_bytes[0][7]=8'h88; expected_bytes[0][8]=8'h99;
    expected_bytes[1][0]=8'hAA; expected_bytes[1][1]=8'hBB; expected_bytes[1][2]=8'hCC;
    expected_bytes[1][3]=8'hDD; expected_bytes[1][4]=8'hEE; expected_bytes[1][5]=8'h12;
    expected_bytes[1][6]=8'h34; expected_bytes[1][7]=8'h56; expected_bytes[1][8]=8'h78;
    expected_bytes[2][0]=8'hDE; expected_bytes[2][1]=8'hAD; expected_bytes[2][2]=8'hBE;
    expected_bytes[2][3]=8'hEF; expected_bytes[2][4]=8'hCA; expected_bytes[2][5]=8'hFE;
    expected_bytes[2][6]=8'h00; expected_bytes[2][7]=8'h01; expected_bytes[2][8]=8'h02;

    for (i=0; i<3; i=i+1) begin
      expected_words[i][0] = {expected_bytes[i][3], expected_bytes[i][2], expected_bytes[i][1], expected_bytes[i][0]};
      expected_words[i][1] = {expected_bytes[i][7], expected_bytes[i][6], expected_bytes[i][5], expected_bytes[i][4]};
      expected_words[i][2] = {24'h0, expected_bytes[i][8]};
      mem_beats[i] = 0;
      dma_beats[i] = 0;
      jtag_bits[i] = 0;
      task_start_time[i] = 0;
      task_runtime[i] = 0;
    end

    $display("\n[TEST] Starting single end-to-end verification: QSPI metadata -> AXI-Lite -> flash/DMA -> JTAG -> target IRQ -> next image");
    repeat (8) @(posedge clk);
    rst_n <= 1'b1;
    repeat (4) @(posedge clk);
    schedule_start <= 1'b1;
    @(posedge clk);
    schedule_start <= 1'b0;

    wait (finished || failed);
    repeat (4) @(posedge clk);

    if (failed) begin
      $display("[FAIL SUMMARY] current_state=%0d phase=%0d sequence=%0d index=%0d",
        scheduler_state, phase_index, dut.u_scheduler.sequence_kind, dut.u_scheduler.sequence_index);
      $display("[FAIL SUMMARY] AXI awaddr=%08h awvalid/ready=%b/%b wdata=%08h wvalid/ready=%b/%b bresp=%b bvalid=%b",
        dut.awaddr, dut.awvalid, dut.awready, dut.wdata, dut.wvalid, dut.wready, dut.bresp, dut.bvalid);
      $display("[FAIL SUMMARY] register_write_error=%b jtag_error=%04h memory_error=%b dma_error=%b",
        dut.register_write_error, dut.jtag_error_code, dut.memory_error, dut.dma_error);
      $fatal(1, "Scheduler failed; see FIRST FAILURE diagnostics above");
    end
    if (!finished) $fatal(1, "Scheduler did not finish all images");
    if (metadata_beats != 12) $fatal(1, "Expected 12 metadata words, got %0d", metadata_beats);
    if (u_flash.read_transactions != 4 || u_flash.read_log_count != 4)
      $fatal(1, "Expected metadata + three QSPI image reads; transactions=%0d log=%0d",
             u_flash.read_transactions, u_flash.read_log_count);
    if (u_flash.read_opcode_log[0] !== 8'hEB || u_flash.read_opcode_log[1] !== 8'hEB ||
        u_flash.read_opcode_log[2] !== 8'hEB || u_flash.read_opcode_log[3] !== 8'hEB)
      $fatal(1, "QSPI read opcode mismatch");
    if (u_flash.read_address_log[0] !== 24'h000000 ||
        u_flash.read_address_log[1] !== 24'h001000 ||
        u_flash.read_address_log[2] !== 24'h010000 ||
        u_flash.read_address_log[3] !== 24'h020000)
      $fatal(1, "Unexpected QSPI read addresses");
    if (target_status_accept_count != 3) $fatal(1, "Expected 3 target configuration status handshakes");
    if (target_task_count != 3) $fatal(1, "Expected 3 target TASK_DONE events, got %0d", target_task_count);
    if (jtag_done_count != 12) $fatal(1, "Expected 12 JTAG completions, got %0d", jtag_done_count);
    if (axi_write_count != 64) $fatal(1, "Expected 64 AXI-Lite control writes, got %0d", axi_write_count);
    for (i=0; i<3; i=i+1) begin
      if (mem_beats[i] != 3 || dma_beats[i] != 3 || jtag_bits[i] != 72)
        $fatal(1, "Image %0d incomplete: mem=%0d dma=%0d JTAGbits=%0d",
          i, mem_beats[i], dma_beats[i], jtag_bits[i]);
    end
    if (task_runtime[0] < TASK_A_TIME || task_runtime[1] < TASK_B_TIME || task_runtime[2] < TASK_C_TIME)
      $fatal(1, "Target task runtime measurement shorter than stimulus");
    if (irq_status[12] || irq_status[13])
      $fatal(1, "Target completion/error interrupt was not acknowledged");
    if (timer_irq) $fatal(1, "Task watchdog must not expire in the nominal test");
    if (phase_index != 2) $fatal(1, "Final phase index should remain 2");

    $display("------------------------------------------------------------");
    $display("PASS: QSPI metadata read and validated before image programming");
    $display("PASS: QSPI image addresses 0x001000, 0x010000 and 0x020000");
    $display("PASS: IDCODE verification and CFG_IN IR selection precede every DR image scan");
    $display("PASS: all 9 bytes per image preserved through memory, DMA and JTAG TDI");
    $display("PASS: target fabric enabled only after configuration status success");
    $display("PASS: variable task runtimes 45 us / 120 us / 15 us drive event-based phase changes");
    $display("PASS: TARGET_TASK_DONE sticky IRQ is acknowledged and advances to the next image");
    $display("PASS: FULL END-TO-END MULTI-IMAGE PIPELINE");
    $display("AXI writes=%0d JTAG completions=%0d QSPI reads=%0d target tasks=%0d",
      axi_write_count, jtag_done_count, u_flash.read_transactions, target_task_count);
    $display("------------------------------------------------------------");
    $finish;
  end

  initial begin
    #5_000_000;
    $fatal(1, "Global timeout: scheduler state=%0d phase=%0d", scheduler_state, phase_index);
  end
endmodule
