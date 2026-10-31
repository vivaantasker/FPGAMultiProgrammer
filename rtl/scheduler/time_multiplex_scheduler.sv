`timescale 1ns/1ps

// Autonomous three-image scheduler. It is a synthesizable AXI4-Lite bus master
// that performs the scheduling function described for the RISC-V firmware.
// It is NOT a RISC-V CPU; see docs/RISCV_CPU_BOUNDARY.md and firmware/.
// Metadata format: NUM_IMAGES records, four little-endian 32-bit words each:
// {flash_byte_offset, bitstream_length_bits, expected_idcode, execution_duration_ms}.
module time_multiplex_scheduler #(
  parameter int ADDR_WIDTH = 32,
  parameter int DATA_WIDTH = 32,
  parameter int NUM_IMAGES = 3,
  parameter int CLK_FREQ_HZ = 100_000_000,
  parameter longint unsigned CYCLES_PER_MS = CLK_FREQ_HZ / 1000,
  parameter int WATCHDOG_CYCLES = 500_000,
  parameter int METADATA_WORDS = NUM_IMAGES * 4,
  parameter logic [31:0] CFG_IN_OPCODE = 32'h0000_0001,
  parameter logic [31:0] IDCODE_OPCODE = 32'h0000_0009,
  parameter logic [31:0] JTAG_IR_LENGTH = 32'd4,
  parameter logic [31:0] JTAG_FREQUENCY_HZ = 32'd1_000_000
)(
  input  logic clk,
  input  logic rst_n,
  input  logic start,

  // Memory-manager stream is routed to this port only while metadata_mode=1.
  output logic metadata_mode,
  input  logic [31:0] metadata_tdata,
  input  logic metadata_tvalid,
  output logic metadata_tready,

  input  logic memory_busy,
  input  logic memory_done,
  input  logic memory_error,
  input  logic dma_busy,
  input  logic dma_done,
  input  logic dma_error,
  input  logic jtag_done,
  input  logic jtag_error,
  input  logic jtag_abort_complete,
  input  logic jtag_idcode_ready,
  input  logic [31:0] jtag_idcode,
  input  logic [15:0] irq_status,
  input  logic target_config_status_valid,
  input  logic target_config_success,
  output logic target_fabric_start_en,

  // AXI4-Lite write master to programmer_control_regs_axi.
  output logic [ADDR_WIDTH-1:0] m_awaddr,
  output logic m_awvalid,
  input  logic m_awready,
  output logic [DATA_WIDTH-1:0] m_wdata,
  output logic [DATA_WIDTH/8-1:0] m_wstrb,
  output logic m_wvalid,
  input  logic m_wready,
  input  logic [1:0] m_bresp,
  input  logic m_bvalid,
  output logic m_bready,

  // Compatibility outputs: active follows target execution; irq is the
  // maximum-runtime watchdog event. Neither is a fixed phase transition timer.
  output logic timer_active,
  output logic timer_irq,
  output logic finished,
  output logic failed,
  output logic [1:0] phase_index,
  output logic [4:0] state_debug,
  output logic [31:0] active_flash_offset,
  output logic [31:0] active_length_bits,
  output logic [31:0] active_duration_ms,
  output logic [15:0] irq_clear_req
);
  // Register offsets implemented in programmer_control_regs_axi.sv.
  localparam logic [31:0] REG_MEM_CTRL    = 32'h0000_0000;
  localparam logic [31:0] REG_MEM_TYPE    = 32'h0000_0004;
  localparam logic [31:0] REG_MEM_ADDR    = 32'h0000_0008;
  localparam logic [31:0] REG_MEM_LENGTH  = 32'h0000_000C;
  localparam logic [31:0] REG_DMA_CTRL    = 32'h0000_1000;
  localparam logic [31:0] REG_DMA_SOURCE  = 32'h0000_1004;
  localparam logic [31:0] REG_DMA_LENGTH  = 32'h0000_1008;
  localparam logic [31:0] REG_JTAG_CTRL   = 32'h0000_2000;
  localparam logic [31:0] REG_JTAG_IRLEN  = 32'h0000_2004;
  localparam logic [31:0] REG_JTAG_DRLEN  = 32'h0000_2008;
  localparam logic [31:0] REG_JTAG_FREQ   = 32'h0000_200C;
  localparam logic [31:0] REG_JTAG_IDCODE = 32'h0000_2010;
  localparam logic [31:0] REG_JTAG_IROP   = 32'h0000_2014;
  localparam logic [31:0] REG_JTAG_MODE   = 32'h0000_2018;

  typedef enum logic [3:0] {
    SEQ_META_CFG, SEQ_META_START, SEQ_IMAGE_CFG, SEQ_IDCODE_IR,
    SEQ_IDCODE, SEQ_CFG_OPCODE, SEQ_IR, SEQ_TRANSFER, SEQ_ABORT
  } sequence_t;

  // Keep the public debug-state values stable for existing waveform scripts:
  // ST_TARGET_STATUS_WAIT remains 7. The IDCODE-IR wait was added at 12.
  typedef enum logic [4:0] {
    ST_IDLE                = 5'd0,
    ST_ISSUE_WRITE         = 5'd1,
    ST_WAIT_WRITE          = 5'd2,
    ST_META_WAIT           = 5'd3,
    ST_IDCODE_WAIT         = 5'd4,
    ST_IR_WAIT             = 5'd5,
    ST_TRANSFER_WAIT       = 5'd6,
    ST_TARGET_STATUS_WAIT  = 5'd7,
    ST_TARGET_RUN          = 5'd8,
    ST_ABORTING            = 5'd9,
    ST_DONE                = 5'd10,
    ST_FAILED              = 5'd11,
    ST_IDCODE_IR_WAIT      = 5'd12,
    ST_ABORT_WAIT          = 5'd13,
    ST_TARGET_RELEASE      = 5'd14
  } state_t;

  state_t state;
  sequence_t sequence_kind;
  logic [3:0] sequence_index;
  logic wr_req_valid, wr_req_ready, wr_done, wr_error;
  logic [31:0] wr_req_addr, wr_req_data;
  logic [31:0] metadata_words [0:METADATA_WORDS-1];
  logic [31:0] image_offsets [0:NUM_IMAGES-1];
  logic [31:0] image_lengths [0:NUM_IMAGES-1];
  logic [31:0] image_durations [0:NUM_IMAGES-1];
  logic [31:0] image_idcodes [0:NUM_IMAGES-1];
  logic [$clog2(METADATA_WORDS+1)-1:0] metadata_word_count;
  logic metadata_valid;
  logic [31:0] watchdog_count;
  logic [63:0] task_watchdog_count;
  logic [63:0] task_watchdog_limit;
  logic seen_memory_done, seen_dma_done, seen_jtag_done;
  logic [3:0] sequence_length;
  logic [31:0] metadata_bits;
  logic unused_target;

  assign metadata_tready = metadata_mode;
  assign wr_req_valid = (state == ST_ISSUE_WRITE);
  assign state_debug = state;
  assign active_flash_offset = image_offsets[phase_index];
  assign active_length_bits = image_lengths[phase_index];
  assign active_duration_ms = image_durations[phase_index];
  assign metadata_bits = METADATA_WORDS * 32;
  // duration_ms is a maximum allowed runtime watchdog, not a fixed schedule
  // slice. A target_task_done IRQ advances the schedule immediately.
  assign task_watchdog_limit = image_durations[phase_index] * CYCLES_PER_MS;
  assign unused_target = ^{target_config_success, jtag_idcode};

  axi_lite_write_master #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) u_axi_write_master (
    .clk(clk), .rst_n(rst_n),
    .req_valid(wr_req_valid), .req_ready(wr_req_ready),
    .req_addr(wr_req_addr[ADDR_WIDTH-1:0]), .req_data(wr_req_data[DATA_WIDTH-1:0]),
    .done(wr_done), .error(wr_error),
    .m_awaddr(m_awaddr), .m_awvalid(m_awvalid), .m_awready(m_awready),
    .m_wdata(m_wdata), .m_wstrb(m_wstrb), .m_wvalid(m_wvalid), .m_wready(m_wready),
    .m_bresp(m_bresp), .m_bvalid(m_bvalid), .m_bready(m_bready)
  );

  always_comb begin
    case (sequence_kind)
      SEQ_META_CFG: sequence_length = 4'd3;
      SEQ_META_START: sequence_length = 4'd1;
      SEQ_IMAGE_CFG: sequence_length = 4'd11;
      SEQ_IDCODE_IR, SEQ_IR: sequence_length = 4'd1;
      SEQ_IDCODE, SEQ_CFG_OPCODE: sequence_length = 4'd2;
      SEQ_TRANSFER, SEQ_ABORT: sequence_length = 4'd3;
      default: sequence_length = 4'd0;
    endcase

    wr_req_addr = 32'h0;
    wr_req_data = 32'h0;
    case (sequence_kind)
      SEQ_META_CFG: begin
        case (sequence_index)
          0: begin wr_req_addr = REG_MEM_TYPE;   wr_req_data = 32'd1; end // QSPI
          1: begin wr_req_addr = REG_MEM_ADDR;   wr_req_data = 32'd0; end
          2: begin wr_req_addr = REG_MEM_LENGTH; wr_req_data = metadata_bits; end
          default: begin end
        endcase
      end
      SEQ_META_START: begin
        wr_req_addr = REG_MEM_CTRL;
        wr_req_data = 32'd1;
      end
      SEQ_IMAGE_CFG: begin
        case (sequence_index)
          0: begin wr_req_addr = REG_MEM_TYPE;   wr_req_data = 32'd1; end
          1: begin wr_req_addr = REG_MEM_ADDR;   wr_req_data = image_offsets[phase_index]; end
          2: begin wr_req_addr = REG_MEM_LENGTH; wr_req_data = image_lengths[phase_index]; end
          3: begin wr_req_addr = REG_DMA_SOURCE; wr_req_data = image_offsets[phase_index]; end
          4: begin wr_req_addr = REG_DMA_LENGTH; wr_req_data = image_lengths[phase_index]; end
          5: begin wr_req_addr = REG_JTAG_IRLEN;  wr_req_data = JTAG_IR_LENGTH; end
          6: begin wr_req_addr = REG_JTAG_IROP;   wr_req_data = IDCODE_OPCODE; end
          7: begin wr_req_addr = REG_JTAG_DRLEN;  wr_req_data = image_lengths[phase_index]; end
          8: begin wr_req_addr = REG_JTAG_FREQ;   wr_req_data = JTAG_FREQUENCY_HZ; end
          9: begin wr_req_addr = REG_JTAG_IDCODE; wr_req_data = image_idcodes[phase_index]; end
          10: begin wr_req_addr = REG_JTAG_MODE;  wr_req_data = 32'd0; end
          default: begin end
        endcase
      end
      SEQ_IDCODE_IR: begin wr_req_addr = REG_JTAG_CTRL; wr_req_data = 32'h0000_0003; end
      SEQ_IDCODE: begin
        if (sequence_index == 0) begin wr_req_addr = REG_JTAG_DRLEN; wr_req_data = 32'd32; end
        else begin wr_req_addr = REG_JTAG_CTRL; wr_req_data = 32'h0000_000D; end
      end
      SEQ_CFG_OPCODE: begin
        if (sequence_index == 0) begin wr_req_addr = REG_JTAG_IROP; wr_req_data = CFG_IN_OPCODE; end
        else begin wr_req_addr = REG_JTAG_DRLEN; wr_req_data = image_lengths[phase_index]; end
      end
      SEQ_IR:        begin wr_req_addr = REG_JTAG_CTRL; wr_req_data = 32'h0000_0003; end
      SEQ_TRANSFER: begin
        case (sequence_index)
          0: begin wr_req_addr = REG_JTAG_CTRL; wr_req_data = 32'h0000_0001; end
          1: begin wr_req_addr = REG_DMA_CTRL;  wr_req_data = 32'h0000_0001; end
          2: begin wr_req_addr = REG_MEM_CTRL;  wr_req_data = 32'h0000_0001; end
          default: begin end
        endcase
      end
      SEQ_ABORT: begin
        case (sequence_index)
          0: begin wr_req_addr = REG_MEM_CTRL;  wr_req_data = 32'h0000_0002; end
          1: begin wr_req_addr = REG_DMA_CTRL;  wr_req_data = 32'h0000_0002; end
          2: begin wr_req_addr = REG_JTAG_CTRL; wr_req_data = 32'h0000_0010; end
          default: begin end
        endcase
      end
      default: begin end
    endcase
  end

  always_comb begin
    metadata_valid = 1'b1;
    for (int n = 0; n < NUM_IMAGES; n++) begin
      if (metadata_words[n*4+1] == 0 || metadata_words[n*4+1][2:0] != 0 ||
          metadata_words[n*4+2] == 0 || metadata_words[n*4+3] == 0 ||
          metadata_words[n*4] < 32'h0000_1000 ||
          metadata_words[n*4] >= (1 << 24) ||
          ({1'b0, metadata_words[n*4]} + (({1'b0, metadata_words[n*4+1]} + 7) >> 3)) > 25'h100_0000)
        metadata_valid = 1'b0;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= ST_IDLE;
      sequence_kind <= SEQ_META_CFG;
      sequence_index <= '0;
      metadata_mode <= 1'b0;
      metadata_word_count <= '0;
      watchdog_count <= '0;
      task_watchdog_count <= '0;
      timer_active <= 1'b0;
      timer_irq <= 1'b0;
      target_fabric_start_en <= 1'b0;
      finished <= 1'b0;
      failed <= 1'b0;
      phase_index <= '0;
      seen_memory_done <= 1'b0;
      seen_dma_done <= 1'b0;
      seen_jtag_done <= 1'b0;
      irq_clear_req <= '0;
      for (int i = 0; i < METADATA_WORDS; i++) metadata_words[i] <= '0;
      for (int i = 0; i < NUM_IMAGES; i++) begin
        image_offsets[i] <= '0;
        image_lengths[i] <= '0;
        image_durations[i] <= '0;
        image_idcodes[i] <= '0;
      end
    end else begin
      timer_irq <= 1'b0;
      irq_clear_req <= '0;

      if (metadata_mode && metadata_tvalid && metadata_tready) begin
        if (metadata_word_count < METADATA_WORDS) begin
          metadata_words[metadata_word_count] <= metadata_tdata;
          metadata_word_count <= metadata_word_count + 1'b1;
        end else begin
          failed <= 1'b1;
          state <= ST_ISSUE_WRITE;
          sequence_kind <= SEQ_ABORT;
          sequence_index <= '0;
        end
      end

      if ((state == ST_META_WAIT) || (state == ST_IDCODE_IR_WAIT) ||
          (state == ST_IDCODE_WAIT) || (state == ST_IR_WAIT) ||
          (state == ST_TRANSFER_WAIT) || (state == ST_TARGET_STATUS_WAIT) ||
          (state == ST_ABORT_WAIT)) begin
        if (watchdog_count < WATCHDOG_CYCLES)
          watchdog_count <= watchdog_count + 1'b1;
      end else begin
        watchdog_count <= '0;
      end

      if (memory_done) seen_memory_done <= 1'b1;
      if (dma_done) seen_dma_done <= 1'b1;
      if (jtag_done) seen_jtag_done <= 1'b1;

      case (state)
        ST_IDLE: begin
          if (start) begin
            metadata_mode <= 1'b1;
            target_fabric_start_en <= 1'b0;
            timer_active <= 1'b0;
            task_watchdog_count <= '0;
            metadata_word_count <= '0;
            phase_index <= '0;
            finished <= 1'b0;
            failed <= 1'b0;
            sequence_kind <= SEQ_META_CFG;
            sequence_index <= '0;
            state <= ST_ISSUE_WRITE;
          end
        end

        ST_ISSUE_WRITE: begin
          if (wr_req_ready) state <= ST_WAIT_WRITE;
        end

        ST_WAIT_WRITE: begin
          if (wr_done) begin
            if (wr_error) begin
              failed <= 1'b1;
              metadata_mode <= 1'b0;
              target_fabric_start_en <= 1'b0;
              timer_active <= 1'b0;
              if (sequence_kind == SEQ_ABORT) begin
                // A failed abort write must not restart the abort sequence forever.
                state <= ST_FAILED;
              end else begin
                sequence_kind <= SEQ_ABORT;
                sequence_index <= '0;
                state <= ST_ISSUE_WRITE;
              end
            end else if ((sequence_index + 1'b1) < sequence_length) begin
              sequence_index <= sequence_index + 1'b1;
              state <= ST_ISSUE_WRITE;
            end else begin
              sequence_index <= '0;
              case (sequence_kind)
                SEQ_META_CFG: begin sequence_kind <= SEQ_META_START; state <= ST_ISSUE_WRITE; end
                SEQ_META_START: begin state <= ST_META_WAIT; end
                SEQ_IMAGE_CFG: begin sequence_kind <= SEQ_IDCODE_IR; state <= ST_ISSUE_WRITE; end
                SEQ_IDCODE_IR: begin state <= ST_IDCODE_IR_WAIT; end
                SEQ_IDCODE: begin state <= ST_IDCODE_WAIT; end
                SEQ_CFG_OPCODE: begin sequence_kind <= SEQ_IR; state <= ST_ISSUE_WRITE; end
                SEQ_IR: begin state <= ST_IR_WAIT; end
                SEQ_TRANSFER: begin
                  state <= ST_TRANSFER_WAIT;
                end
                SEQ_ABORT: begin state <= ST_ABORT_WAIT; end
                default: begin failed <= 1'b1; state <= ST_FAILED; end
              endcase
            end
          end
        end

        ST_META_WAIT: begin
          if (memory_error || (watchdog_count >= WATCHDOG_CYCLES)) begin
            failed <= 1'b1;
            metadata_mode <= 1'b0;
            target_fabric_start_en <= 1'b0;
            timer_active <= 1'b0;
            sequence_kind <= SEQ_ABORT;
            sequence_index <= '0;
            state <= ST_ISSUE_WRITE;
          end else if (memory_done) begin
            metadata_mode <= 1'b0;
            if ((metadata_word_count != METADATA_WORDS) || !metadata_valid) begin
              failed <= 1'b1;
              sequence_kind <= SEQ_ABORT;
              sequence_index <= '0;
              state <= ST_ISSUE_WRITE;
            end else begin
              for (int i = 0; i < NUM_IMAGES; i++) begin
                image_offsets[i] <= metadata_words[i*4+0];
                image_lengths[i] <= metadata_words[i*4+1];
                image_idcodes[i] <= metadata_words[i*4+2];
                image_durations[i] <= metadata_words[i*4+3];
              end
              sequence_kind <= SEQ_IMAGE_CFG;
              sequence_index <= '0;
              state <= ST_ISSUE_WRITE;
            end
          end
        end

        ST_IDCODE_IR_WAIT: begin
          if (jtag_error || (watchdog_count >= WATCHDOG_CYCLES)) begin
            failed <= 1'b1;
            sequence_kind <= SEQ_ABORT;
            sequence_index <= '0;
            state <= ST_ISSUE_WRITE;
          end else if (jtag_done) begin
            sequence_kind <= SEQ_IDCODE;
            sequence_index <= '0;
            state <= ST_ISSUE_WRITE;
          end
        end

        ST_IDCODE_WAIT: begin
          if (jtag_error || (watchdog_count >= WATCHDOG_CYCLES)) begin
            failed <= 1'b1;
            sequence_kind <= SEQ_ABORT;
            sequence_index <= '0;
            state <= ST_ISSUE_WRITE;
          end else if (jtag_done && jtag_idcode_ready) begin
            if (jtag_idcode != image_idcodes[phase_index]) begin
              failed <= 1'b1;
              sequence_kind <= SEQ_ABORT;
              sequence_index <= '0;
              state <= ST_ISSUE_WRITE;
            end else begin
              sequence_kind <= SEQ_CFG_OPCODE;
              sequence_index <= '0;
              state <= ST_ISSUE_WRITE;
            end
          end
        end

        ST_IR_WAIT: begin
          if (jtag_error || (watchdog_count >= WATCHDOG_CYCLES)) begin
            failed <= 1'b1;
            sequence_kind <= SEQ_ABORT;
            sequence_index <= '0;
            state <= ST_ISSUE_WRITE;
          end else if (jtag_done) begin
            // Clear the completion latches before launching the DR/data phase.
            // This prevents a short transfer from completing before the flags
            // are cleared by the final AXI-Lite start write.
            seen_memory_done <= 1'b0;
            seen_dma_done <= 1'b0;
            seen_jtag_done <= 1'b0;
            sequence_kind <= SEQ_TRANSFER;
            sequence_index <= '0;
            state <= ST_ISSUE_WRITE;
          end
        end

        ST_TRANSFER_WAIT: begin
          if (memory_error || dma_error || jtag_error || (watchdog_count >= WATCHDOG_CYCLES)) begin
            failed <= 1'b1;
            sequence_kind <= SEQ_ABORT;
            sequence_index <= '0;
            state <= ST_ISSUE_WRITE;
          end else if ((seen_memory_done || memory_done) &&
                       (seen_dma_done || dma_done) && (seen_jtag_done || jtag_done)) begin
            state <= ST_TARGET_STATUS_WAIT;
          end
        end

        ST_TARGET_STATUS_WAIT: begin
          if (watchdog_count >= WATCHDOG_CYCLES) begin
            failed <= 1'b1;
            sequence_kind <= SEQ_ABORT;
            sequence_index <= '0;
            state <= ST_ISSUE_WRITE;
          end else if (target_config_status_valid) begin
            if (!target_config_success) begin
              failed <= 1'b1;
              sequence_kind <= SEQ_ABORT;
              sequence_index <= '0;
              state <= ST_ISSUE_WRITE;
            end else begin
              // Clear stale target events before releasing the newly configured
              // fabric. The fabric runs until its own TASK_DONE/TASK_ERROR IRQ.
              irq_clear_req[2]  <= 1'b1;
              irq_clear_req[3]  <= 1'b1;
              irq_clear_req[4]  <= 1'b1;
              irq_clear_req[5]  <= 1'b1;
              irq_clear_req[7]  <= 1'b1;
              irq_clear_req[8]  <= 1'b1;
              irq_clear_req[9]  <= 1'b1;
              irq_clear_req[12] <= 1'b1;
              irq_clear_req[13] <= 1'b1;
              // Give the sticky interrupt hub a full cycle to acknowledge stale
              // target events before the newly configured fabric is released.
              state <= ST_TARGET_RELEASE;
            end
          end
        end

        ST_TARGET_RELEASE: begin
          if (!irq_status[12] && !irq_status[13]) begin
            task_watchdog_count <= '0;
            target_fabric_start_en <= 1'b1;
            timer_active <= 1'b1;
            state <= ST_TARGET_RUN;
          end
        end

        ST_TARGET_RUN: begin
          // duration_ms is a maximum-runtime safety watchdog only. It never
          // schedules a normal image change; target_task_done does that.
          if (irq_status[13]) begin
            target_fabric_start_en <= 1'b0;
            timer_active <= 1'b0;
            irq_clear_req[13] <= 1'b1;
            failed <= 1'b1;
            sequence_kind <= SEQ_ABORT;
            sequence_index <= '0;
            state <= ST_ISSUE_WRITE;
          end else if (irq_status[12]) begin
            target_fabric_start_en <= 1'b0;
            timer_active <= 1'b0;
            irq_clear_req[12] <= 1'b1;
            task_watchdog_count <= '0;
            if (phase_index == NUM_IMAGES-1) begin
              finished <= 1'b1;
              state <= ST_DONE;
            end else begin
              phase_index <= phase_index + 1'b1;
              sequence_kind <= SEQ_IMAGE_CFG;
              sequence_index <= '0;
              state <= ST_ISSUE_WRITE;
            end
          end else if ((task_watchdog_limit != 0) &&
                       (task_watchdog_count >= task_watchdog_limit)) begin
            target_fabric_start_en <= 1'b0;
            timer_active <= 1'b0;
            timer_irq <= 1'b1; // Sticky IRQ bit 11 records a task watchdog expiry.
            failed <= 1'b1;
            sequence_kind <= SEQ_ABORT;
            sequence_index <= '0;
            state <= ST_ISSUE_WRITE;
          end else begin
            task_watchdog_count <= task_watchdog_count + 1'b1;
          end
        end

        ST_ABORT_WAIT: begin
          // Do not report final failure until the JTAG TAP has completed its
          // five-clock Test-Logic-Reset recovery and the memory/DMA engines are
          // inactive. Bound the wait in case an acknowledgement is lost.
          if (!memory_busy && !dma_busy && jtag_abort_complete) begin
            state <= ST_FAILED;
          end else if (watchdog_count >= WATCHDOG_CYCLES) begin
            state <= ST_FAILED;
          end
        end

        ST_DONE: begin
          finished <= 1'b1;
          timer_active <= 1'b0;
          target_fabric_start_en <= 1'b0;
        end

        ST_FAILED: begin
          failed <= 1'b1;
          timer_active <= 1'b0;
          target_fabric_start_en <= 1'b0;
        end

        default: begin
          failed <= 1'b1;
          target_fabric_start_en <= 1'b0;
          timer_active <= 1'b0;
          sequence_kind <= SEQ_ABORT;
          sequence_index <= '0;
          state <= ST_ISSUE_WRITE;
        end
      endcase
    end
  end
endmodule
