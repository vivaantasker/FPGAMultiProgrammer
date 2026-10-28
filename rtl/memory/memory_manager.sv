`timescale 1ns/1ps

module memory_manager #(
  parameter int ADDR_WIDTH = 24,
  parameter int DATA_WIDTH = 32,
  parameter int MEM_TYPE_WIDTH = 3,
  parameter int CLK_FREQ_HZ = 100_000_000,
  parameter int SPI_CLK_FREQ_HZ = 10_000_000,
  parameter int QSPI_CLK_FREQ_HZ = 10_000_000,
  parameter int OSPI_CLK_FREQ_HZ = 10_000_000,
  parameter int SPI_DUMMY_CYCLES = 0,
  parameter int QSPI_DUMMY_CYCLES = 2,
  parameter int OSPI_DUMMY_CYCLES = 2,
  parameter logic [7:0] SPI_READ_OPCODE = 8'h03,
  parameter logic [7:0] QSPI_READ_OPCODE = 8'hEB,
  parameter logic [7:0] OSPI_READ_OPCODE = 8'hEC
)(
  input  logic clk,
  input  logic rst_n,
  input  logic [MEM_TYPE_WIDTH-1:0] memory_type,
  input  logic [ADDR_WIDTH-1:0] addr,
  input  logic [15:0] length,
  input  logic read_req,
  output logic busy,
  output logic done,
  output logic error,
  output logic [DATA_WIDTH-1:0] read_data,

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
  import programmer_pkg::*;

  logic request_d;
  logic request_pulse;
  logic spi_busy, spi_done, spi_error;
  logic qspi_busy, qspi_done, qspi_error;
  logic ospi_busy, ospi_done, ospi_error;
  logic [DATA_WIDTH-1:0] spi_read_data;
  logic [DATA_WIDTH-1:0] qspi_read_data;
  logic [DATA_WIDTH-1:0] ospi_read_data;
  memory_type_t selected_type;
  logic active;

  assign request_pulse = read_req && !request_d && !active;
  assign busy = active;

  spi_controller #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH),
    .CLK_FREQ_HZ(CLK_FREQ_HZ),
    .SCLK_FREQ_HZ(SPI_CLK_FREQ_HZ),
    .DUMMY_CYCLES(SPI_DUMMY_CYCLES),
    .READ_OPCODE(SPI_READ_OPCODE)
  ) u_spi (
    .clk(clk),
    .rst_n(rst_n),
    .addr(addr),
    .length(length),
    .read_req(request_pulse && (memory_type == MEM_SPI)),
    .cfg_read_opcode(SPI_READ_OPCODE),
    .cfg_dummy_cycles(SPI_DUMMY_CYCLES),
    .cfg_clk_divider((CLK_FREQ_HZ / (2 * SPI_CLK_FREQ_HZ)) < 1 ? 16'd1 : (CLK_FREQ_HZ / (2 * SPI_CLK_FREQ_HZ))),
    .busy(spi_busy),
    .done(spi_done),
    .error(spi_error),
    .read_data(spi_read_data),
    .sclk(sclk),
    .cs_n(cs_n),
    .mosi(mosi),
    .miso(miso)
  );

  qspi_controller #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH),
    .CLK_FREQ_HZ(CLK_FREQ_HZ),
    .SCLK_FREQ_HZ(QSPI_CLK_FREQ_HZ),
    .DUMMY_CYCLES(QSPI_DUMMY_CYCLES),
    .READ_OPCODE(QSPI_READ_OPCODE)
  ) u_qspi (
    .clk(clk),
    .rst_n(rst_n),
    .addr(addr),
    .length(length),
    .read_req(request_pulse && (memory_type == MEM_QSPI)),
    .cfg_read_opcode(QSPI_READ_OPCODE),
    .cfg_dummy_cycles(QSPI_DUMMY_CYCLES),
    .cfg_clk_divider((CLK_FREQ_HZ / (2 * QSPI_CLK_FREQ_HZ)) < 1 ? 16'd1 : (CLK_FREQ_HZ / (2 * QSPI_CLK_FREQ_HZ))),
    .busy(qspi_busy),
    .done(qspi_done),
    .error(qspi_error),
    .read_data(qspi_read_data),
    .sclk(qspi_sclk),
    .cs_n(qspi_cs_n),
    .io(qspi_io)
  );

  ospi_controller #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH),
    .CLK_FREQ_HZ(CLK_FREQ_HZ),
    .SCLK_FREQ_HZ(OSPI_CLK_FREQ_HZ),
    .DUMMY_CYCLES(OSPI_DUMMY_CYCLES),
    .READ_OPCODE(OSPI_READ_OPCODE)
  ) u_ospi (
    .clk(clk),
    .rst_n(rst_n),
    .addr(addr),
    .length(length),
    .read_req(request_pulse && (memory_type == MEM_OSPI)),
    .cfg_read_opcode(OSPI_READ_OPCODE),
    .cfg_dummy_cycles(OSPI_DUMMY_CYCLES),
    .cfg_clk_divider((CLK_FREQ_HZ / (2 * OSPI_CLK_FREQ_HZ)) < 1 ? 16'd1 : (CLK_FREQ_HZ / (2 * OSPI_CLK_FREQ_HZ))),
    .busy(ospi_busy),
    .done(ospi_done),
    .error(ospi_error),
    .read_data(ospi_read_data),
    .sclk(ospi_sclk),
    .cs_n(ospi_cs_n),
    .io(ospi_io)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      request_d <= 1'b0;
      selected_type <= MEM_SPI;
      active <= 1'b0;
      done <= 1'b0;
      error <= 1'b0;
      read_data <= '0;
    end else begin
      request_d <= read_req;
      done <= 1'b0;
      error <= 1'b0;

      if (request_pulse) begin
        case (memory_type)
          MEM_SPI: begin
            selected_type <= MEM_SPI;
            active <= 1'b1;
          end
          MEM_QSPI: begin
            selected_type <= MEM_QSPI;
            active <= 1'b1;
          end
          MEM_OSPI: begin
            selected_type <= MEM_OSPI;
            active <= 1'b1;
          end
          default: begin
            active <= 1'b0;
            error <= 1'b1;
          end
        endcase
      end

      case (selected_type)
        MEM_SPI: begin
          read_data <= spi_read_data;
          if (active && (spi_done || spi_error)) begin
            done <= spi_done;
            error <= spi_error;
            active <= 1'b0;
          end
        end
        MEM_QSPI: begin
          read_data <= qspi_read_data;
          if (active && (qspi_done || qspi_error)) begin
            done <= qspi_done;
            error <= qspi_error;
            active <= 1'b0;
          end
        end
        MEM_OSPI: begin
          read_data <= ospi_read_data;
          if (active && (ospi_done || ospi_error)) begin
            done <= ospi_done;
            error <= ospi_error;
            active <= 1'b0;
          end
        end
        default: begin
          if (!active) read_data <= '0;
        end
      endcase
    end
  end

endmodule
