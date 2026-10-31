`timescale 1ns/1ps

// Protocol-level JTAG target model for RTL verification only.
// The default 4-bit IR and IDCODE opcode are a model contract, not a claim
// about any unselected physical FPGA. Override parameters to model another
// target's documented register map when that target is selected.
module jtag_target_model #(
  parameter int IR_LENGTH = 4,
  parameter logic [IR_LENGTH-1:0] IDCODE_INSTRUCTION = {{(IR_LENGTH-1){1'b0}}, 1'b1},
  parameter logic [31:0] IDCODE_VALUE = 32'h1234_5678,
  parameter logic [31:0] OTHER_DR_VALUE = 32'hA5A5_5A5A
)(
  input  logic rst_n,
  input  logic tck,
  input  logic tms,
  input  logic tdi,
  output wire tdo,
  output logic [31:0] idcode
);
  import programmer_pkg::*;

  tap_state_t tap_state;
  logic [IR_LENGTH-1:0] ir_shift;
  logic [IR_LENGTH-1:0] active_instruction;
  logic [31:0] dr_shift;
  logic tdo_q;

  // Model the electrical behavior of a JTAG target: TDO is driven only while
  // the TAP is in Shift-IR or Shift-DR, and is high impedance elsewhere.
  // The data bit is registered on falling TCK so it is stable before the next
  // rising edge at which the host samples it.
  assign tdo = ((tap_state == TAP_SHIFT_IR) || (tap_state == TAP_SHIFT_DR)) ? tdo_q : 1'bz;

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

  assign idcode = IDCODE_VALUE;

  // IEEE 1149.1 target-side data timing: TDO changes on falling TCK.
  always_ff @(negedge tck or negedge rst_n) begin
    if (!rst_n) begin
      tdo_q <= 1'b0;
    end else begin
      case (tap_state)
        TAP_SHIFT_IR: tdo_q <= ir_shift[0];
        TAP_SHIFT_DR: tdo_q <= dr_shift[0];
        default:      tdo_q <= 1'b0;
      endcase
    end
  end

  always_ff @(posedge tck or negedge rst_n) begin
    if (!rst_n) begin
      tap_state <= TAP_TEST_LOGIC_RESET;
      ir_shift <= {{(IR_LENGTH-1){1'b0}}, 1'b1};
      active_instruction <= IDCODE_INSTRUCTION;
      dr_shift <= IDCODE_VALUE;
    end else begin
      // Register actions use the TAP state occupied immediately before this
      // TCK rising edge, as defined by the IEEE 1149.1 state/clock relationship.
      case (tap_state)
        TAP_CAPTURE_IR: begin
          ir_shift <= {{(IR_LENGTH-2){1'b0}}, 2'b01};
        end
        TAP_SHIFT_IR: begin
          ir_shift <= {tdi, ir_shift[IR_LENGTH-1:1]};
        end
        TAP_UPDATE_IR: begin
          active_instruction <= ir_shift;
        end
        TAP_CAPTURE_DR: begin
          if (active_instruction == IDCODE_INSTRUCTION)
            dr_shift <= IDCODE_VALUE;
          else
            dr_shift <= OTHER_DR_VALUE;
        end
        TAP_SHIFT_DR: begin
          dr_shift <= {tdi, dr_shift[31:1]};
        end
        default: begin end
      endcase

      tap_state <= tap_next(tap_state, tms);
      if (tap_next(tap_state, tms) == TAP_TEST_LOGIC_RESET)
        active_instruction <= IDCODE_INSTRUCTION;
    end
  end
endmodule
