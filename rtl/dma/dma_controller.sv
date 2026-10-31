`timescale 1ns/1ps

// Single-entry, backpressure-aware DMA stream bridge.
// transfer_length is in bits and must be non-zero and byte-aligned.
// The upstream memory manager consumes source_address; this block validates
// and forwards its stream without generating memory reads itself.
module dma_controller #(
  parameter int DATA_WIDTH = 32
)(
  input  logic clk,
  input  logic rst_n,
  input  logic start,
  input  logic abort,
  input  logic [31:0] source_address,
  input  logic [31:0] transfer_length,
  input  logic [DATA_WIDTH-1:0] s_axis_tdata,
  input  logic [DATA_WIDTH/8-1:0] s_axis_tkeep,
  input  logic s_axis_tvalid,
  output logic s_axis_tready,
  input  logic s_axis_tlast,
  output logic [DATA_WIDTH-1:0] m_axis_tdata,
  output logic [DATA_WIDTH/8-1:0] m_axis_tkeep,
  output logic m_axis_tvalid,
  input  logic m_axis_tready,
  output logic m_axis_tlast,
  output logic done,
  output logic error,
  output logic busy
);
  localparam int BYTES_PER_WORD = DATA_WIDTH / 8;
  localparam int COUNT_WIDTH = 33;

  logic active;
  logic [COUNT_WIDTH-1:0] expected_bits;
  logic [COUNT_WIDTH-1:0] input_bits_seen;
  logic [COUNT_WIDTH-1:0] output_bits_seen;
  logic [COUNT_WIDTH-1:0] input_beat_bits;
  logic [COUNT_WIDTH-1:0] output_beat_bits;
  logic [BYTES_PER_WORD-1:0] input_expected_keep;
  logic [BYTES_PER_WORD-1:0] output_expected_keep;
  logic input_expected_last;
  logic output_expected_last;
  logic input_keep_ok;
  logic output_keep_ok;
  logic input_fire;
  logic output_fire;

  function automatic logic [BYTES_PER_WORD-1:0] keep_for_bytes(input logic [31:0] nbytes);
    logic [BYTES_PER_WORD-1:0] result;
    result = '0;
    for (int i = 0; i < BYTES_PER_WORD; i++) begin
      if (i < nbytes) result[i] = 1'b1;
    end
    return result;
  endfunction

  function automatic logic keep_is_contiguous(input logic [BYTES_PER_WORD-1:0] keep);
    logic seen_zero;
    seen_zero = 1'b0;
    keep_is_contiguous = 1'b1;
    for (int i = 0; i < BYTES_PER_WORD; i++) begin
      if (keep[i] == 1'b0) begin
        seen_zero = 1'b1;
      end else if (keep[i] == 1'b1) begin
        if (seen_zero) keep_is_contiguous = 1'b0;
      end else begin
        keep_is_contiguous = 1'b0;
      end
    end
  endfunction

  always_comb begin
    input_beat_bits  = $countones(s_axis_tkeep) * 8;
    output_beat_bits = $countones(m_axis_tkeep) * 8;

    input_expected_keep  = '0;
    output_expected_keep = '0;
    if (active && (input_bits_seen < expected_bits)) begin
      if ((expected_bits - input_bits_seen) >= DATA_WIDTH)
        input_expected_keep = '1;
      else
        input_expected_keep = keep_for_bytes((expected_bits - input_bits_seen) / 8);
    end
    if (active && (output_bits_seen < expected_bits)) begin
      if ((expected_bits - output_bits_seen) >= DATA_WIDTH)
        output_expected_keep = '1;
      else
        output_expected_keep = keep_for_bytes((expected_bits - output_bits_seen) / 8);
    end

    input_expected_last  = ((input_bits_seen + input_beat_bits) == expected_bits);
    output_expected_last = ((output_bits_seen + output_beat_bits) == expected_bits);

    input_keep_ok = active && keep_is_contiguous(s_axis_tkeep) &&
                    (input_beat_bits != 0) &&
                    (s_axis_tkeep == input_expected_keep) &&
                    ((input_bits_seen + input_beat_bits) <= expected_bits);
    output_keep_ok = active && keep_is_contiguous(m_axis_tkeep) &&
                     (output_beat_bits != 0) &&
                     (m_axis_tkeep == output_expected_keep) &&
                     ((output_bits_seen + output_beat_bits) <= expected_bits);

    // A beat is accepted only when the transaction still expects source data
    // and the one-entry output register is empty or will be consumed this edge.
    // Gating start/abort prevents acknowledging a source beat on a cycle when
    // the transaction is being cancelled/restarted.
    s_axis_tready = active && !start && !abort &&
                    (input_bits_seen < expected_bits) &&
                    (!m_axis_tvalid || m_axis_tready);
    input_fire  = s_axis_tvalid && s_axis_tready;
    output_fire = m_axis_tvalid && m_axis_tready;
    busy = active;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      active           <= 1'b0;
      expected_bits    <= '0;
      input_bits_seen  <= '0;
      output_bits_seen <= '0;
      m_axis_tdata     <= '0;
      m_axis_tkeep     <= '0;
      m_axis_tvalid    <= 1'b0;
      m_axis_tlast     <= 1'b0;
      done             <= 1'b0;
      error            <= 1'b0;
    end else begin
      // done/error are one-cycle events; the controller is responsible for
      // latching completion/error status if it needs persistence.
      done  <= 1'b0;
      error <= 1'b0;

      if (start && active) begin
        // A second start while busy is a protocol error.
        active        <= 1'b0;
        m_axis_tvalid <= 1'b0;
        m_axis_tlast  <= 1'b0;
        error         <= 1'b1;
      end else if (abort && active) begin
        active        <= 1'b0;
        m_axis_tvalid <= 1'b0;
        m_axis_tlast  <= 1'b0;
        error         <= 1'b1;
      end else if (start && !active) begin
        m_axis_tvalid    <= 1'b0;
        m_axis_tlast     <= 1'b0;
        input_bits_seen  <= '0;
        output_bits_seen <= '0;
        if ((transfer_length == 0) || (transfer_length[2:0] != 0) ||
            (DATA_WIDTH < 8) || ((DATA_WIDTH % 8) != 0)) begin
          active        <= 1'b0;
          expected_bits <= '0;
          error         <= 1'b1;
        end else begin
          active        <= 1'b1;
          expected_bits <= {1'b0, transfer_length};
        end
      end else if (active) begin
        // Any malformed accepted beat aborts the transfer. If input and output
        // handshakes coincide, an error on either side takes priority; no stale
        // valid beat is retained after the transaction has failed.
        if ((output_fire && (!output_keep_ok || (m_axis_tlast != output_expected_last))) ||
            (input_fire  && (!input_keep_ok  || (s_axis_tlast != input_expected_last)))) begin
          active        <= 1'b0;
          m_axis_tvalid <= 1'b0;
          m_axis_tlast  <= 1'b0;
          error         <= 1'b1;
        end else begin
          // Pop first. Crucial fix: clear TVALID on every non-final output
          // handshake. If a new input beat is accepted on the same edge, the
          // input block below replaces this empty slot and reasserts TVALID.
          if (output_fire) begin
            output_bits_seen <= output_bits_seen + output_beat_bits;
            if (m_axis_tlast) begin
              active        <= 1'b0;
              m_axis_tvalid <= 1'b0;
              m_axis_tlast  <= 1'b0;
              done          <= 1'b1;
            end else begin
              m_axis_tvalid <= 1'b0;
              m_axis_tlast  <= 1'b0;
            end
          end

          // Push. This later assignment intentionally replaces a beat popped
          // in the same cycle, permitting one accepted beat per clock at full
          // throughput while preserving stable output under backpressure.
          if (input_fire) begin
            input_bits_seen <= input_bits_seen + input_beat_bits;
            m_axis_tdata    <= s_axis_tdata;
            m_axis_tkeep    <= s_axis_tkeep;
            m_axis_tvalid   <= 1'b1;
            m_axis_tlast    <= s_axis_tlast;
          end
        end
      end
    end
  end

  // Address decode is performed by memory_manager in this streaming design.
  logic unused_source_address;
  always_comb unused_source_address = ^source_address;
endmodule
