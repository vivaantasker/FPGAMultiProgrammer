`timescale 1ns/1ps

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
  input  logic [15:0] length,
  input  logic read_req,
  input  logic [7:0] cfg_read_opcode = READ_OPCODE,
  input  logic [15:0] cfg_dummy_cycles = DUMMY_CYCLES,
  input  logic [15:0] cfg_clk_divider = ((CLK_FREQ_HZ / (2 * SERIAL_CLK_HZ)) < 1) ? 16'd1 : (CLK_FREQ_HZ / (2 * SERIAL_CLK_HZ)),
  output logic busy,
  output logic done,
  output logic error,
  output logic [DATA_WIDTH-1:0] read_data,
  output logic sclk,
  output logic cs_n,
  input  logic [LANES-1:0] io_in,
  output logic [LANES-1:0] io_out,
  output logic io_oe
);
  localparam int DEFAULT_HALF_PERIOD_RAW = (CLK_FREQ_HZ / (2 * SERIAL_CLK_HZ));
  localparam int DEFAULT_HALF_PERIOD = (DEFAULT_HALF_PERIOD_RAW < 1) ? 1 : DEFAULT_HALF_PERIOD_RAW;

  typedef enum logic [2:0] {
    ST_IDLE,
    ST_COMMAND,
    ST_ADDRESS,
    ST_DUMMY,
    ST_DATA
  } state_t;

  state_t state;
  logic [ADDR_WIDTH-1:0] address_shift;
  logic [$clog2(ADDR_WIDTH+1)-1:0] address_cycles_left;
  logic [3:0] command_bits_sent;
  logic [15:0] dummy_cycles_left;
  logic [15:0] data_bits_left;
  logic [31:0] divider_count;
  logic [15:0] clk_divider_latched;
  logic [7:0] opcode_latched;
  logic [15:0] dummy_cycles_latched;
  logic read_req_d;
  logic [LANES-1:0] read_lanes;

  assign read_lanes = io_in;

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

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= ST_IDLE;
      busy <= 1'b0;
      done <= 1'b0;
      error <= 1'b0;
      read_data <= '0;
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
    end else begin
      done <= 1'b0;
      error <= 1'b0;
      read_req_d <= read_req;

      if (state == ST_IDLE) begin
        sclk <= 1'b0;
        cs_n <= 1'b1;
        divider_count <= '0;
        if (read_req && !read_req_d) begin
          if (length == 0 || (length % LANES) != 0 || cfg_clk_divider == 0) begin
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
            clk_divider_latched <= (cfg_clk_divider == 0) ? DEFAULT_HALF_PERIOD : cfg_clk_divider;
            opcode_latched <= cfg_read_opcode;
            dummy_cycles_latched <= cfg_dummy_cycles;
            read_data <= '0;
          end
        end
      end else if (divider_count == clk_divider_latched - 1) begin
        divider_count <= '0;
        sclk <= ~sclk;

        if (!sclk) begin
          case (state)
            ST_COMMAND: begin
              if (CMD_LANES == 1 && command_bits_sent < 7)
                command_bits_sent <= command_bits_sent + 1'b1;
              else begin
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

            ST_DATA: begin
              read_data <= (read_data << LANES) | read_lanes;
              if (data_bits_left <= LANES) begin
                data_bits_left <= '0;
                state <= ST_IDLE;
                busy <= 1'b0;
                done <= 1'b1;
                cs_n <= 1'b1;
                sclk <= 1'b0;
              end else begin
                data_bits_left <= data_bits_left - LANES;
              end
            end

            default: begin
              state <= ST_IDLE;
              busy <= 1'b0;
              cs_n <= 1'b1;
              sclk <= 1'b0;
              error <= 1'b1;
            end
          endcase
        end
      end else begin
        divider_count <= divider_count + 1'b1;
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
    if (DATA_WIDTH < LANES)
      $error("DATA_WIDTH must be at least LANES");
    if (SERIAL_CLK_HZ < 1)
      $error("SERIAL_CLK_HZ must be positive");
  end
endmodule
