`timescale 1ns/1ps

// Generic SPI/QSPI/OSPI read sequencer with a backpressure-aware AXI-Stream
// output. length is a bit count; this implementation requires byte-aligned
// lengths and a number of bits divisible by LANES. The first sampled serial
// bit/lane is placed in stream_data[0], so a downstream LSB-first JTAG shifter
// emits the received stream in chronological bit order.
module serial_flash_read_engine #(
  parameter int ADDR_WIDTH = 24,
  parameter int DATA_WIDTH = 32,
  parameter int LANES = 4,
  parameter int CMD_LANES = 1,
  parameter int CLK_FREQ_HZ = 100_000_000,
  parameter int SERIAL_CLK_HZ = 10_000_000,
  parameter int DUMMY_CYCLES = 2,
  parameter logic [7:0] READ_OPCODE = 8'hEB
)(
  input  logic clk,
  input  logic rst_n,
  input  logic [ADDR_WIDTH-1:0] addr,
  input  logic [31:0] length,
  input  logic read_req,
  input  logic abort = 1'b0,
  input  logic [7:0] cfg_read_opcode = READ_OPCODE,
  input  logic [15:0] cfg_dummy_cycles = DUMMY_CYCLES,
  input  logic [15:0] cfg_clk_divider = ((CLK_FREQ_HZ / (2 * SERIAL_CLK_HZ)) < 1) ? 16'd1 : (CLK_FREQ_HZ / (2 * SERIAL_CLK_HZ)),
  output logic busy,
  output logic done,
  output logic error,
  output logic [DATA_WIDTH-1:0] read_data,
  output logic [DATA_WIDTH-1:0] m_axis_tdata,
  output logic [DATA_WIDTH/8-1:0] m_axis_tkeep,
  output logic m_axis_tvalid,
  input  logic m_axis_tready = 1'b1,
  output logic m_axis_tlast,
  output logic sclk,
  output logic cs_n,
  input  logic [LANES-1:0] io_in,
  output logic [LANES-1:0] io_out,
  output logic io_oe
);
  localparam int DEFAULT_HALF_PERIOD_RAW = CLK_FREQ_HZ / (2 * SERIAL_CLK_HZ);
  localparam int DEFAULT_HALF_PERIOD = (DEFAULT_HALF_PERIOD_RAW < 1) ? 1 : DEFAULT_HALF_PERIOD_RAW;
  localparam int WORD_COUNT_WIDTH = (DATA_WIDTH <= 2) ? 1 : $clog2(DATA_WIDTH + 1);

  typedef enum logic [2:0] {
    ST_IDLE, ST_COMMAND, ST_ADDRESS, ST_DUMMY, ST_DATA, ST_STREAM_WAIT
  } state_t;

  state_t state;
  logic [ADDR_WIDTH-1:0] address_shift;
  logic [$clog2(ADDR_WIDTH+1)-1:0] address_cycles_left;
  logic [3:0] command_bits_sent;
  logic [15:0] dummy_cycles_left;
  logic [31:0] data_bits_left;
  logic [31:0] divider_count;
  logic [15:0] clk_divider_latched;
  logic [7:0] opcode_latched;
  logic [15:0] dummy_cycles_latched;
  logic read_req_d;
  logic [LANES-1:0] read_lanes;
  logic [DATA_WIDTH-1:0] stream_word;
  logic [DATA_WIDTH-1:0] stream_word_next;
  logic [WORD_COUNT_WIDTH-1:0] stream_bit_count;
  logic [WORD_COUNT_WIDTH:0] stream_bits_after_symbol;
  logic [DATA_WIDTH/8-1:0] final_keep;
  // AXI-Stream valid/ready is a fabric-clock handshake, independent of the
  // serial-clock divider. Remember an accepted beat while finishing the
  // required SCLK high/low phases; never leave TVALID high after a handshake.
  logic stream_beat_accepted;
  logic stream_last_accepted;

  assign read_lanes = io_in;
  assign stream_bits_after_symbol = stream_bit_count + LANES;

  always_comb begin
    io_out = '0;
    io_oe = 1'b0;
    case (state)
      ST_COMMAND: begin
        io_oe = 1'b1;
        if (CMD_LANES == 1)
          io_out[0] = opcode_latched[7-command_bits_sent];
        else
          io_out = opcode_latched[7 -: LANES];
      end
      ST_ADDRESS: begin
        io_oe = 1'b1;
        io_out = address_shift[ADDR_WIDTH-1 -: LANES];
      end
      default: begin
        io_oe = 1'b0;
        io_out = '0;
      end
    endcase
  end

  // Construct the next stream word without reversing serial bit order.
  always_comb begin
    stream_word_next = stream_word;
    for (int lane = 0; lane < LANES; lane++) begin
      if ((stream_bit_count + lane) < DATA_WIDTH)
        stream_word_next[stream_bit_count + lane] = read_lanes[lane];
    end

    final_keep = '0;
    for (int b = 0; b < DATA_WIDTH/8; b++) begin
      if (b < ((stream_bits_after_symbol + 7) / 8))
        final_keep[b] = 1'b1;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= ST_IDLE;
      busy <= 1'b0;
      done <= 1'b0;
      error <= 1'b0;
      read_data <= '0;
      m_axis_tdata <= '0;
      m_axis_tkeep <= '0;
      m_axis_tvalid <= 1'b0;
      m_axis_tlast <= 1'b0;
      sclk <= 1'b0;
      cs_n <= 1'b1;
      address_shift <= '0;
      address_cycles_left <= '0;
      command_bits_sent <= '0;
      dummy_cycles_left <= '0;
      data_bits_left <= '0;
      divider_count <= '0;
      clk_divider_latched <= DEFAULT_HALF_PERIOD;
      opcode_latched <= READ_OPCODE;
      dummy_cycles_latched <= DUMMY_CYCLES;
      read_req_d <= 1'b0;
      stream_word <= '0;
      stream_bit_count <= '0;
      stream_beat_accepted <= 1'b0;
      stream_last_accepted <= 1'b0;
    end else begin
      done <= 1'b0;
      error <= 1'b0;
      read_req_d <= read_req;

      if (abort && state != ST_IDLE) begin
        state <= ST_IDLE;
        busy <= 1'b0;
        cs_n <= 1'b1;
        sclk <= 1'b0;
        m_axis_tvalid <= 1'b0;
        m_axis_tlast <= 1'b0;
        divider_count <= '0;
        data_bits_left <= '0;
        stream_word <= '0;
        stream_bit_count <= '0;
        stream_beat_accepted <= 1'b0;
        stream_last_accepted <= 1'b0;
        error <= 1'b1;
      end else begin
        case (state)
          ST_IDLE: begin
            sclk <= 1'b0;
            cs_n <= 1'b1;
            divider_count <= '0;
            m_axis_tvalid <= 1'b0;
            m_axis_tlast <= 1'b0;
            stream_beat_accepted <= 1'b0;
            stream_last_accepted <= 1'b0;
            if (read_req && !read_req_d) begin
              if ((length == 0) || (length[2:0] != 0) || ((length % LANES) != 0) ||
                  (cfg_clk_divider == 0) || (DATA_WIDTH % LANES != 0)) begin
                error <= 1'b1;
              end else begin
                state <= ST_COMMAND;
                busy <= 1'b1;
                cs_n <= 1'b0;
                address_shift <= addr;
                address_cycles_left <= ADDR_WIDTH / LANES;
                command_bits_sent <= '0;
                dummy_cycles_left <= cfg_dummy_cycles;
                data_bits_left <= length;
                clk_divider_latched <= cfg_clk_divider;
                opcode_latched <= cfg_read_opcode;
                dummy_cycles_latched <= cfg_dummy_cycles;
                read_data <= '0;
                stream_word <= '0;
                stream_bit_count <= '0;
                m_axis_tdata <= '0;
                m_axis_tkeep <= '0;
                m_axis_tvalid <= 1'b0;
                m_axis_tlast <= 1'b0;
              end
            end
          end

          ST_STREAM_WAIT: begin
            // AXI-Stream handshakes happen on every clk edge, not only when
            // the serial divider expires. Retire TVALID immediately on the
            // first TVALID&TREADY edge so a downstream buffer becoming ready
            // again cannot accept the same flash beat twice. The accepted
            // flag lets us finish the serial high phase, then hold SCLK low
            // for a complete half-period before sampling the next symbol.
            if (m_axis_tvalid && m_axis_tready && !stream_beat_accepted) begin
              m_axis_tvalid <= 1'b0;
              stream_beat_accepted <= 1'b1;
              stream_last_accepted <= m_axis_tlast;
            end

            if (divider_count == clk_divider_latched - 1) begin
              divider_count <= '0;
              if (sclk) begin
                sclk <= 1'b0;
              end else if (stream_beat_accepted || (m_axis_tvalid && m_axis_tready)) begin
                if ((stream_beat_accepted && stream_last_accepted) ||
                    (!stream_beat_accepted && m_axis_tvalid && m_axis_tready && m_axis_tlast)) begin
                  m_axis_tlast <= 1'b0;
                  stream_beat_accepted <= 1'b0;
                  stream_last_accepted <= 1'b0;
                  state <= ST_IDLE;
                  busy <= 1'b0;
                  cs_n <= 1'b1;
                  done <= 1'b1;
                end else begin
                  m_axis_tlast <= 1'b0;
                  stream_beat_accepted <= 1'b0;
                  stream_last_accepted <= 1'b0;
                  state <= ST_DATA;
                end
              end
            end else begin
              divider_count <= divider_count + 1'b1;
            end
          end

          default: begin
            if (divider_count == clk_divider_latched - 1) begin
              divider_count <= '0;
              sclk <= ~sclk;

              // SPI mode-0 style timing: sample incoming data on SCLK rising
              // edges, but advance MOSI opcode/address/dummy state on falling
              // edges. This keeps outgoing bits stable across the sampling edge.
              if (sclk) begin
                case (state)
                  ST_COMMAND: begin
                    if ((CMD_LANES == 1) && (command_bits_sent < 7)) begin
                      command_bits_sent <= command_bits_sent + 1'b1;
                    end else begin
                      state <= ST_ADDRESS;
                      command_bits_sent <= '0;
                    end
                  end
                  ST_ADDRESS: begin
                    address_shift <= address_shift << LANES;
                    if (address_cycles_left == 1) begin
                      if (dummy_cycles_latched == 0)
                        state <= ST_DATA;
                      else
                        state <= ST_DUMMY;
                    end else begin
                      address_cycles_left <= address_cycles_left - 1'b1;
                    end
                  end
                  ST_DUMMY: begin
                    if (dummy_cycles_left <= 1)
                      state <= ST_DATA;
                    else
                      dummy_cycles_left <= dummy_cycles_left - 1'b1;
                  end
                  default: begin end
                endcase
              end else if (state == ST_DATA) begin
                // Incoming lanes are sampled immediately before this generated
                // rising edge becomes visible to the external flash model.
                read_data <= (read_data << LANES) | read_lanes;
                stream_word <= stream_word_next;
                if ((stream_bits_after_symbol >= DATA_WIDTH) || (data_bits_left <= LANES)) begin
                  m_axis_tdata <= stream_word_next;
                  if (stream_bits_after_symbol >= DATA_WIDTH)
                    m_axis_tkeep <= '1;
                  else
                    m_axis_tkeep <= final_keep;
                  m_axis_tvalid <= 1'b1;
                  m_axis_tlast <= (data_bits_left <= LANES);
                  stream_beat_accepted <= 1'b0;
                  stream_last_accepted <= 1'b0;
                  stream_word <= '0;
                  stream_bit_count <= '0;
                  state <= ST_STREAM_WAIT;
                end else begin
                  stream_bit_count <= stream_bit_count + LANES;
                end
                if (data_bits_left <= LANES)
                  data_bits_left <= '0;
                else
                  data_bits_left <= data_bits_left - LANES;
              end else if ((state != ST_COMMAND) && (state != ST_ADDRESS) &&
                           (state != ST_DUMMY) && (state != ST_DATA)) begin
                state <= ST_IDLE;
                busy <= 1'b0;
                cs_n <= 1'b1;
                sclk <= 1'b0;
                error <= 1'b1;
              end
            end else begin
              divider_count <= divider_count + 1'b1;
            end
          end
        endcase
      end
    end
  end

  initial begin
    if (LANES < 1 || LANES > 8 || (LANES & (LANES - 1)) != 0)
      $error("LANES must be 1, 2, 4, or 8");
    if (CMD_LANES != 1 && CMD_LANES != LANES)
      $error("CMD_LANES must be 1 or equal to LANES");
    if ((ADDR_WIDTH % LANES) != 0)
      $error("ADDR_WIDTH must be an integer number of lane transfers");
    if (DATA_WIDTH < LANES || (DATA_WIDTH % LANES) != 0 || (DATA_WIDTH % 8) != 0)
      $error("DATA_WIDTH must be byte-sized and divisible by LANES");
    if (SERIAL_CLK_HZ < 1)
      $error("SERIAL_CLK_HZ must be positive");
  end
endmodule
