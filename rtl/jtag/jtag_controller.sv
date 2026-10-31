`timescale 1ns/1ps

// Device-independent IEEE 1149.1 serial scan controller.
//
// scan_start starts one scan transaction. scan_ir selects IR (1) or DR (0).
// tx_data/tx_valid/tx_ready form a word stream consumed LSB-first. The scan
// length is expressed in BITS and is taken from ir_length or dr_length.
// TDO bits are returned LSB-first in DATA_WIDTH-bit words; a final partial
// word is right-aligned. Set capture_idcode for a 32-bit IDCODE read; set
// verify_idcode as well to compare it against expected_idcode. Arbitrary 32-bit
// DR scans are not implicitly treated as IDCODE reads.
//
// This block deliberately does not encode any FPGA-vendor configuration
// instruction or bitstream format. The caller supplies the IR opcode/length.
module jtag_controller #(
  parameter int DATA_WIDTH = 32,
  parameter int MAX_IR_LENGTH = 32,
  parameter int unsigned MAX_DR_LENGTH = 32'hFFFF_FFFF,
  parameter int CLK_FREQ_HZ = 100_000_000
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
  // Number of valid low-order bits in rx_data for the beat marked by rx_valid.
  // Full words report DATA_WIDTH; a final partial word reports 1..DATA_WIDTH-1.
  output logic [$clog2(DATA_WIDTH+1)-1:0] rx_bit_count,
  output logic done,
  output logic [31:0] idcode,
  output logic idcode_ready,
  // Sticky until the next scan_start; used by the main controller to avoid
  // accepting a new programming command before abort recovery has finished.
  output logic abort_complete,
  output logic [15:0] status,
  output logic [15:0] error_code,
  output logic tck,
  output logic tms,
  output logic tdi,
  input  logic tdo,
  input  logic scan_start,
  input  logic scan_ir,
  // capture_idcode marks a 32-bit IDCODE read; verify_idcode additionally
  // compares the captured value against expected_idcode.
  input  logic capture_idcode,
  input  logic verify_idcode,
  input  logic abort
);
  import programmer_pkg::*;

  localparam int WORD_INDEX_WIDTH = (DATA_WIDTH <= 2) ? 1 : $clog2(DATA_WIDTH);
  localparam logic [15:0] JTAG_ERR_BAD_FREQUENCY = 16'h0001;
  localparam logic [15:0] JTAG_ERR_BAD_LENGTH    = 16'h0002;
  localparam logic [15:0] JTAG_ERR_IDCODE        = 16'h0003;
  localparam logic [15:0] JTAG_ERR_ABORTED       = 16'h0004;

  typedef enum logic [3:0] {
    J_IDLE,
    J_RESET,
    J_GO_IDLE,
    J_NAV_DR_SELECT,
    J_NAV_DR_CAPTURE,
    J_NAV_DR_SHIFT,
    J_NAV_IR_SELECT_DR,
    J_NAV_IR_SELECT_IR,
    J_NAV_IR_CAPTURE,
    J_NAV_IR_SHIFT,
    J_SHIFT,
    J_EXIT1,
    J_RETURN_IDLE,
    J_COMPLETE,
    J_ABORT_RESET
  } operation_state_t;

  operation_state_t operation_state;
  tap_state_t tap_state;
  logic [DATA_WIDTH-1:0] tx_word;
  logic tx_word_valid;
  logic [DATA_WIDTH-1:0] rx_shift;
  logic [31:0] idcode_shift;
  logic [31:0] scan_length;
  logic [31:0] bits_shifted;
  logic [31:0] half_period;
  logic [31:0] divider_count;
  logic [2:0] reset_clocks;
  logic [WORD_INDEX_WIDTH-1:0] tx_bit_index;
  logic [WORD_INDEX_WIDTH-1:0] rx_bit_index;
  logic active;
  logic active_scan_ir;
  logic active_capture_idcode;
  logic active_verify_idcode;
  logic tap_initialized;
  logic abort_pending;
  logic abort_reset_complete;
  logic [DATA_WIDTH-1:0] rx_next_word;
  logic [63:0] half_period_denominator;
  logic [63:0] half_period_numerator;
  logic [31:0] half_period_calc;

  // TCK is a registered output; the phase counter only advances when a
  // complete half-period is allowed. During starvation it pauses at TCK-low.
  // A high phase always completes before the clock is allowed to stop. This
  // avoids data-valid-dependent combinational clock gating and runt pulses.
  logic tck_phase_enable;
  always_comb begin
    tck_phase_enable = (operation_state != J_SHIFT) || tx_word_valid || tck || abort_pending;
    half_period_denominator = 64'd2 * jtag_frequency;
    half_period_numerator = 64'(CLK_FREQ_HZ);
    if (half_period_denominator == 0)
      half_period_calc = 32'd1;
    else begin
      half_period_calc = (half_period_numerator + half_period_denominator - 1) /
                         half_period_denominator;
      if (half_period_calc == 0) half_period_calc = 32'd1;
    end
  end

  function automatic tap_state_t tap_next(input tap_state_t s, input logic m);
    case (s)
      TAP_TEST_LOGIC_RESET: tap_next = m ? TAP_TEST_LOGIC_RESET : TAP_RUN_TEST_IDLE;
      TAP_RUN_TEST_IDLE:   tap_next = m ? TAP_SELECT_DR_SCAN : TAP_RUN_TEST_IDLE;
      TAP_SELECT_DR_SCAN:  tap_next = m ? TAP_SELECT_IR_SCAN : TAP_CAPTURE_DR;
      TAP_CAPTURE_DR:      tap_next = m ? TAP_EXIT1_DR : TAP_SHIFT_DR;
      TAP_SHIFT_DR:        tap_next = m ? TAP_EXIT1_DR : TAP_SHIFT_DR;
      TAP_EXIT1_DR:        tap_next = m ? TAP_UPDATE_DR : TAP_PAUSE_DR;
      TAP_PAUSE_DR:        tap_next = m ? TAP_EXIT2_DR : TAP_PAUSE_DR;
      TAP_EXIT2_DR:        tap_next = m ? TAP_UPDATE_DR : TAP_SHIFT_DR;
      TAP_UPDATE_DR:       tap_next = m ? TAP_SELECT_DR_SCAN : TAP_RUN_TEST_IDLE;
      TAP_SELECT_IR_SCAN:  tap_next = m ? TAP_TEST_LOGIC_RESET : TAP_CAPTURE_IR;
      TAP_CAPTURE_IR:      tap_next = m ? TAP_EXIT1_IR : TAP_SHIFT_IR;
      TAP_SHIFT_IR:        tap_next = m ? TAP_EXIT1_IR : TAP_SHIFT_IR;
      TAP_EXIT1_IR:        tap_next = m ? TAP_UPDATE_IR : TAP_PAUSE_IR;
      TAP_PAUSE_IR:        tap_next = m ? TAP_EXIT2_IR : TAP_PAUSE_IR;
      TAP_EXIT2_IR:        tap_next = m ? TAP_UPDATE_IR : TAP_SHIFT_IR;
      TAP_UPDATE_IR:       tap_next = m ? TAP_SELECT_DR_SCAN : TAP_RUN_TEST_IDLE;
      default:             tap_next = TAP_TEST_LOGIC_RESET;
    endcase
  endfunction

  // Include the currently sampled TDO bit in the word returned on this clock.
  // LSB-first serial order is represented as the corresponding binary word.
  always_comb begin
    rx_next_word = rx_shift;
    rx_next_word[rx_bit_index] = tdo;
  end

  // Stream backpressure: accept a new source word only when the shifter needs it.
  always_comb begin
    tx_ready = active && !abort_pending && !tx_word_valid && (bits_shifted < scan_length);
    // Permit the first stream beat to be accepted on the same cycle as scan_start.
    if (!active && scan_start && !abort &&
        (jtag_frequency != 0) && (jtag_frequency <= (CLK_FREQ_HZ / 2)) &&
        ((scan_ir && (ir_length != 0) && (ir_length <= MAX_IR_LENGTH)) ||
         (!scan_ir && (dr_length != 0) && (dr_length <= MAX_DR_LENGTH))) &&
        (!(capture_idcode || verify_idcode) || (!scan_ir && (dr_length == 32)))) begin
      tx_ready = 1'b1;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      operation_state <= J_IDLE;
      tap_state <= TAP_TEST_LOGIC_RESET;
      tx_word <= '0;
      tx_word_valid <= 1'b0;
      rx_shift <= '0;
      rx_data <= '0;
      rx_valid <= 1'b0;
      rx_bit_count <= '0;
      done <= 1'b0;
      idcode_shift <= '0;
      idcode <= '0;
      idcode_ready <= 1'b0;
      abort_complete <= 1'b0;
      status <= '0;
      error_code <= '0;
      tck <= 1'b0;
      tms <= 1'b1;
      tdi <= 1'b0;
      scan_length <= '0;
      bits_shifted <= '0;
      half_period <= 32'd1;
      divider_count <= '0;
      reset_clocks <= '0;
      tx_bit_index <= '0;
      rx_bit_index <= '0;
      active <= 1'b0;
      active_scan_ir <= 1'b0;
      active_capture_idcode <= 1'b0;
      active_verify_idcode <= 1'b0;
      tap_initialized <= 1'b0;
      abort_pending <= 1'b0;
      abort_reset_complete <= 1'b0;
    end else begin
      // rx_valid and done are event pulses. idcode_ready is deliberately
      // sticky: a controller may observe it several cycles after the scan.
      rx_valid <= 1'b0;
      done <= 1'b0;

      if (abort && active && !abort_pending) begin
        // Abort is synchronous to clk. Never truncate a high TCK phase: retain
        // TMS/TDI until the normal half-period expires, then begin five TMS=1
        // clocks to force the physical TAP into Test-Logic-Reset.
        abort_pending <= 1'b1;
        abort_reset_complete <= 1'b0;
        abort_complete <= 1'b0;
        tx_word_valid <= 1'b0;
        reset_clocks <= '0;
        operation_state <= J_ABORT_RESET;
        status <= '0;
        if (!tck) begin
          divider_count <= '0;
          tms <= 1'b1;
          tdi <= 1'b0;
        end else if (divider_count >= (half_period - 1)) begin
          divider_count <= '0;
          tck <= 1'b0;
          tms <= 1'b1;
          tdi <= 1'b0;
        end else begin
          divider_count <= divider_count + 1'b1;
        end
      end else if (abort && !active && !abort_pending) begin
        // Cancel a coincident scan_start if abort arrives before active is set.
        // There is no current high TCK phase to finish; report recovery complete.
        operation_state <= J_IDLE;
        tx_word_valid <= 1'b0;
        tck <= 1'b0;
        tms <= 1'b1;
        tdi <= 1'b0;
        divider_count <= '0;
        status <= '0;
        idcode_ready <= 1'b0;
        abort_complete <= 1'b1;
        error_code <= JTAG_ERR_ABORTED;
      end else begin
        if (scan_start && !active) begin
          status <= '0;
          abort_complete <= 1'b0;
          error_code <= '0;
          idcode_ready <= 1'b0;
          rx_valid <= 1'b0;
          rx_bit_count <= '0;
          idcode <= '0;
          idcode_shift <= '0;
          rx_shift <= '0;
          rx_bit_index <= '0;
          tx_bit_index <= '0;
          tx_word_valid <= 1'b0;
          bits_shifted <= '0;
          reset_clocks <= '0;
          divider_count <= '0;
          tck <= 1'b0;
          // Reset the TAP only for the first transaction after hardware reset
          // or abort. Later IR and DR scans start from Run-Test/Idle and retain
          // the selected instruction across separate transactions.
          tms <= tap_initialized ? 1'b0 : 1'b1;
          tdi <= 1'b0;
          active_scan_ir <= scan_ir;
          active_capture_idcode <= capture_idcode || verify_idcode;
          active_verify_idcode <= verify_idcode;
          scan_length <= scan_ir ? ir_length : dr_length;

          if ((jtag_frequency == 0) || (jtag_frequency > (CLK_FREQ_HZ / 2))) begin
            active <= 1'b0;
            operation_state <= J_IDLE;
            error_code <= JTAG_ERR_BAD_FREQUENCY;
          end else if ((scan_ir && ((ir_length == 0) || (ir_length > MAX_IR_LENGTH))) ||
                       (!scan_ir && ((dr_length == 0) || (dr_length > MAX_DR_LENGTH))) ||
                       ((capture_idcode || verify_idcode) && (scan_ir || (dr_length != 32)))) begin
            active <= 1'b0;
            operation_state <= J_IDLE;
            error_code <= JTAG_ERR_BAD_LENGTH;
          end else begin
            active <= 1'b1;
            operation_state <= tap_initialized ? J_GO_IDLE : J_RESET;
            // Use ceiling division so the generated TCK does not exceed the
            // requested frequency when the ratio is not an integer.
            half_period <= half_period_calc;
            if (tx_valid && tx_ready) begin
              tx_word <= tx_data;
              tx_word_valid <= 1'b1;
              tx_bit_index <= '0;
            end
          end
        end else begin
          // Word input and scan sequencer share this clock. A word may be queued
          // during TAP navigation, and no TCK rising edge occurs while data starves.
          if (tx_valid && tx_ready) begin
            tx_word <= tx_data;
            tx_word_valid <= 1'b1;
            tx_bit_index <= '0;
            if (!tck) tdi <= tx_data[0];
          end

          if (active) begin
            if (!tck_phase_enable) begin
              // Starved in Shift-IR/Shift-DR while TCK is low: do not allow a
              // late tx_valid assertion to inherit a nearly-expired divider.
              divider_count <= '0;
              tck <= 1'b0;
            end else if (divider_count >= (half_period - 1)) begin
              divider_count <= '0;

              if (tck) begin
                // Falling TCK edge: update TMS/TDI for the next sampling edge.
                tck <= 1'b0;
                case (operation_state)
                  J_RESET: begin tms <= 1'b1; tdi <= 1'b0; end
                  J_GO_IDLE: begin tms <= 1'b0; tdi <= 1'b0; end
                  J_NAV_DR_SELECT: begin tms <= 1'b1; tdi <= 1'b0; end
                  J_NAV_DR_CAPTURE: begin tms <= 1'b0; tdi <= 1'b0; end
                  J_NAV_DR_SHIFT: begin tms <= 1'b0; tdi <= 1'b0; end
                  J_NAV_IR_SELECT_DR: begin tms <= 1'b1; tdi <= 1'b0; end
                  J_NAV_IR_SELECT_IR: begin tms <= 1'b1; tdi <= 1'b0; end
                  J_NAV_IR_CAPTURE: begin tms <= 1'b0; tdi <= 1'b0; end
                  J_NAV_IR_SHIFT: begin tms <= 1'b0; tdi <= 1'b0; end
                  J_SHIFT: begin
                    if (tx_word_valid) begin
                      tms <= (bits_shifted == (scan_length - 1));
                      tdi <= tx_word[tx_bit_index];
                    end else if (tx_valid && tx_ready) begin
                      // First bit of a just-accepted word; tx_data is stable now.
                      tms <= (bits_shifted == (scan_length - 1));
                      tdi <= tx_data[0];
                    end else begin
                      tms <= 1'b0;
                      tdi <= 1'b0;
                    end
                  end
                  J_EXIT1: begin tms <= 1'b1; tdi <= 1'b0; end
                  J_RETURN_IDLE: begin tms <= 1'b0; tdi <= 1'b0; end
                  J_COMPLETE: begin
                    done <= 1'b1;
                    tms <= 1'b0;
                    tdi <= 1'b0;
                    active <= 1'b0;
                    tx_word_valid <= 1'b0;
                    abort_pending <= 1'b0;
                    if (!active_scan_ir && active_capture_idcode && (scan_length == 32)) begin
                      idcode_ready <= 1'b1;
                      if (!active_verify_idcode || (idcode == expected_idcode)) begin
                        status <= 16'h0001;
                        error_code <= '0;
                      end else begin
                        status <= '0;
                        error_code <= JTAG_ERR_IDCODE;
                      end
                    end else begin
                      status <= 16'h0001;
                    end
                  end
                  J_ABORT_RESET: begin
                    // Drive reset TMS on each falling edge; finish only after
                    // the fifth reset clock's full high phase has ended.
                    tms <= 1'b1;
                    tdi <= 1'b0;
                    if (abort_reset_complete) begin
                      active <= 1'b0;
                      operation_state <= J_IDLE;
                      abort_pending <= 1'b0;
                      abort_reset_complete <= 1'b0;
                      abort_complete <= 1'b1;
                      tap_initialized <= 1'b1;
                      tx_word_valid <= 1'b0;
                      error_code <= JTAG_ERR_ABORTED;
                      status <= '0;
                      done <= 1'b1;
                    end
                  end
                  default: begin tms <= 1'b0; tdi <= 1'b0; end
                endcase
              end else begin
                // Rising TCK edge. Sample TDO before target shift-register updates.
                // A missing data word stalls only at TCK-low, preserving JTAG timing.
                if ((operation_state == J_SHIFT) && !tx_word_valid) begin
                  tck <= 1'b0;
                end else begin
                  tck <= 1'b1;
                  tap_state <= tap_next(tap_state, tms);
                  case (operation_state)
                    J_RESET: begin
                      if (reset_clocks == 3'd4) begin
                        reset_clocks <= '0;
                        tap_initialized <= 1'b1;
                        operation_state <= J_GO_IDLE;
                      end else begin
                        reset_clocks <= reset_clocks + 1'b1;
                      end
                    end
                    J_ABORT_RESET: begin
                      tms <= 1'b1;
                      tdi <= 1'b0;
                      if (reset_clocks == 3'd4) begin
                        // The fifth TCK rising edge has reached TLR. Leave the
                        // output high for its full half-period; J_ABORT_RESET's
                        // falling-edge branch completes recovery.
                        abort_reset_complete <= 1'b1;
                      end else begin
                        reset_clocks <= reset_clocks + 1'b1;
                      end
                    end
                    J_GO_IDLE: begin
                      operation_state <= active_scan_ir ? J_NAV_IR_SELECT_DR : J_NAV_DR_SELECT;
                    end
                    J_NAV_DR_SELECT: operation_state <= J_NAV_DR_CAPTURE;
                    J_NAV_DR_CAPTURE: operation_state <= J_NAV_DR_SHIFT;
                    J_NAV_DR_SHIFT: operation_state <= J_SHIFT;
                    J_NAV_IR_SELECT_DR: operation_state <= J_NAV_IR_SELECT_IR;
                    J_NAV_IR_SELECT_IR: operation_state <= J_NAV_IR_CAPTURE;
                    J_NAV_IR_CAPTURE: operation_state <= J_NAV_IR_SHIFT;
                    J_NAV_IR_SHIFT: operation_state <= J_SHIFT;
                    J_SHIFT: begin
                      // Both TX and RX scan streams are serialized LSB-first.
                      rx_shift[rx_bit_index] <= tdo;
                      if (!active_scan_ir && active_capture_idcode && (bits_shifted < 32)) begin
                        idcode_shift <= {tdo, idcode_shift[31:1]};
                        if (bits_shifted == 31)
                          idcode <= {tdo, idcode_shift[31:1]};
                      end

                      bits_shifted <= bits_shifted + 1'b1;
                      if (rx_bit_index == DATA_WIDTH - 1) begin
                        rx_data <= rx_next_word;
                        rx_valid <= 1'b1;
                        rx_bit_count <= DATA_WIDTH;
                        rx_shift <= '0;
                        rx_bit_index <= '0;
                      end else if (bits_shifted == (scan_length - 1)) begin
                        rx_data <= rx_next_word;
                        rx_valid <= 1'b1;
                        rx_bit_count <= rx_bit_index + 1'b1;
                        rx_shift <= '0;
                        rx_bit_index <= '0;
                      end else begin
                        rx_bit_index <= rx_bit_index + 1'b1;
                      end

                      if ((tx_bit_index == DATA_WIDTH - 1) ||
                          (bits_shifted == (scan_length - 1))) begin
                        tx_bit_index <= '0;
                        tx_word_valid <= 1'b0;
                      end else begin
                        tx_bit_index <= tx_bit_index + 1'b1;
                      end

                      if (bits_shifted == (scan_length - 1))
                        operation_state <= J_EXIT1;
                    end
                    J_EXIT1: operation_state <= J_RETURN_IDLE;
                    J_RETURN_IDLE: operation_state <= J_COMPLETE;
                    default: operation_state <= J_IDLE;
                  endcase
                end
              end
            end else begin
              divider_count <= divider_count + 1'b1;
            end
          end
        end
      end
    end
  end
endmodule
