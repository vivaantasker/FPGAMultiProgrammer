`timescale 1ns/1ps

// Flash selector and stream mux. length is measured in bits and must be
// byte-aligned. A complete read is surfaced as AXI-Stream beats; read_data is
// retained as a legacy rolling view of the most recently sampled DATA_WIDTH bits.
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
  input  logic [31:0] length,
  input  logic read_req,
  input  logic abort = 1'b0,
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

  logic request_d, request_pulse, active;
  logic spi_busy, spi_done, spi_error;
  logic qspi_busy, qspi_done, qspi_error;
  logic ospi_busy, ospi_done, ospi_error;
  logic [DATA_WIDTH-1:0] spi_read_data, qspi_read_data, ospi_read_data;
  logic [DATA_WIDTH-1:0] spi_tdata, qspi_tdata, ospi_tdata;
  logic [DATA_WIDTH/8-1:0] spi_tkeep, qspi_tkeep, ospi_tkeep;
  logic spi_tvalid, qspi_tvalid, ospi_tvalid;
  logic spi_tlast, qspi_tlast, ospi_tlast;
  logic selected_spi_ready, selected_qspi_ready, selected_ospi_ready;
  memory_type_t selected_type;

  localparam logic [15:0] SPI_DUMMY_CYCLES_CFG = 16'(SPI_DUMMY_CYCLES);
  localparam logic [15:0] QSPI_DUMMY_CYCLES_CFG = 16'(QSPI_DUMMY_CYCLES);
  localparam logic [15:0] OSPI_DUMMY_CYCLES_CFG = 16'(OSPI_DUMMY_CYCLES);
  localparam logic [15:0] SPI_CLK_DIVIDER_CFG =
      ((CLK_FREQ_HZ / (2 * SPI_CLK_FREQ_HZ)) < 1) ? 16'd1 : 16'(CLK_FREQ_HZ / (2 * SPI_CLK_FREQ_HZ));
  localparam logic [15:0] QSPI_CLK_DIVIDER_CFG =
      ((CLK_FREQ_HZ / (2 * QSPI_CLK_FREQ_HZ)) < 1) ? 16'd1 : 16'(CLK_FREQ_HZ / (2 * QSPI_CLK_FREQ_HZ));
  localparam logic [15:0] OSPI_CLK_DIVIDER_CFG =
      ((CLK_FREQ_HZ / (2 * OSPI_CLK_FREQ_HZ)) < 1) ? 16'd1 : 16'(CLK_FREQ_HZ / (2 * OSPI_CLK_FREQ_HZ));

  assign request_pulse = read_req && !request_d && !active;
  assign busy = active;
  assign selected_spi_ready = m_axis_tready && (selected_type == MEM_SPI);
  assign selected_qspi_ready = m_axis_tready && (selected_type == MEM_QSPI);
  assign selected_ospi_ready = m_axis_tready && (selected_type == MEM_OSPI);

  spi_controller #(
    .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .CLK_FREQ_HZ(CLK_FREQ_HZ),
    .SCLK_FREQ_HZ(SPI_CLK_FREQ_HZ), .DUMMY_CYCLES(SPI_DUMMY_CYCLES),
    .READ_OPCODE(SPI_READ_OPCODE)
  ) u_spi (
    .clk(clk), .rst_n(rst_n), .addr(addr), .length(length),
    .read_req(request_pulse && (memory_type == MEM_SPI)), .abort(abort),
    .cfg_read_opcode(SPI_READ_OPCODE), .cfg_dummy_cycles(SPI_DUMMY_CYCLES_CFG),
    .cfg_clk_divider(SPI_CLK_DIVIDER_CFG),
    .busy(spi_busy), .done(spi_done), .error(spi_error), .read_data(spi_read_data),
    .m_axis_tdata(spi_tdata), .m_axis_tkeep(spi_tkeep), .m_axis_tvalid(spi_tvalid),
    .m_axis_tready(selected_spi_ready), .m_axis_tlast(spi_tlast),
    .sclk(sclk), .cs_n(cs_n), .mosi(mosi), .miso(miso)
  );

  qspi_controller #(
    .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .CLK_FREQ_HZ(CLK_FREQ_HZ),
    .SCLK_FREQ_HZ(QSPI_CLK_FREQ_HZ), .DUMMY_CYCLES(QSPI_DUMMY_CYCLES),
    .READ_OPCODE(QSPI_READ_OPCODE)
  ) u_qspi (
    .clk(clk), .rst_n(rst_n), .addr(addr), .length(length),
    .read_req(request_pulse && (memory_type == MEM_QSPI)), .abort(abort),
    .cfg_read_opcode(QSPI_READ_OPCODE), .cfg_dummy_cycles(QSPI_DUMMY_CYCLES_CFG),
    .cfg_clk_divider(QSPI_CLK_DIVIDER_CFG),
    .busy(qspi_busy), .done(qspi_done), .error(qspi_error), .read_data(qspi_read_data),
    .m_axis_tdata(qspi_tdata), .m_axis_tkeep(qspi_tkeep), .m_axis_tvalid(qspi_tvalid),
    .m_axis_tready(selected_qspi_ready), .m_axis_tlast(qspi_tlast),
    .sclk(qspi_sclk), .cs_n(qspi_cs_n), .io(qspi_io)
  );

  ospi_controller #(
    .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .CLK_FREQ_HZ(CLK_FREQ_HZ),
    .SCLK_FREQ_HZ(OSPI_CLK_FREQ_HZ), .DUMMY_CYCLES(OSPI_DUMMY_CYCLES),
    .READ_OPCODE(OSPI_READ_OPCODE)
  ) u_ospi (
    .clk(clk), .rst_n(rst_n), .addr(addr), .length(length),
    .read_req(request_pulse && (memory_type == MEM_OSPI)), .abort(abort),
    .cfg_read_opcode(OSPI_READ_OPCODE), .cfg_dummy_cycles(OSPI_DUMMY_CYCLES_CFG),
    .cfg_clk_divider(OSPI_CLK_DIVIDER_CFG),
    .busy(ospi_busy), .done(ospi_done), .error(ospi_error), .read_data(ospi_read_data),
    .m_axis_tdata(ospi_tdata), .m_axis_tkeep(ospi_tkeep), .m_axis_tvalid(ospi_tvalid),
    .m_axis_tready(selected_ospi_ready), .m_axis_tlast(ospi_tlast),
    .sclk(ospi_sclk), .cs_n(ospi_cs_n), .io(ospi_io)
  );

  always_comb begin
    m_axis_tdata = '0;
    m_axis_tkeep = '0;
    m_axis_tvalid = 1'b0;
    m_axis_tlast = 1'b0;
    read_data = '0;
    case (selected_type)
      MEM_SPI: begin
        m_axis_tdata = spi_tdata; m_axis_tkeep = spi_tkeep;
        m_axis_tvalid = spi_tvalid; m_axis_tlast = spi_tlast; read_data = spi_read_data;
      end
      MEM_QSPI: begin
        m_axis_tdata = qspi_tdata; m_axis_tkeep = qspi_tkeep;
        m_axis_tvalid = qspi_tvalid; m_axis_tlast = qspi_tlast; read_data = qspi_read_data;
      end
      MEM_OSPI: begin
        m_axis_tdata = ospi_tdata; m_axis_tkeep = ospi_tkeep;
        m_axis_tvalid = ospi_tvalid; m_axis_tlast = ospi_tlast; read_data = ospi_read_data;
      end
      default: begin end
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      request_d <= 1'b0;
      selected_type <= MEM_SPI;
      active <= 1'b0;
      done <= 1'b0;
      error <= 1'b0;
    end else begin
      request_d <= read_req;
      done <= 1'b0;
      error <= 1'b0;

      if (request_pulse) begin
        if (length == 0 || length[2:0] != 0) begin
          active <= 1'b0;
          error <= 1'b1;
        end else begin
          case (memory_type)
            MEM_SPI, MEM_QSPI, MEM_OSPI: begin
              selected_type <= memory_type_t'(memory_type);
              active <= 1'b1;
            end
            default: begin
              active <= 1'b0;
              error <= 1'b1;
            end
          endcase
        end
      end

      if (abort && active) begin
        active <= 1'b0;
        error <= 1'b1;
      end else if (active) begin
        case (selected_type)
          MEM_SPI: if (spi_done || spi_error) begin done <= spi_done; error <= spi_error; active <= 1'b0; end
          MEM_QSPI: if (qspi_done || qspi_error) begin done <= qspi_done; error <= qspi_error; active <= 1'b0; end
          MEM_OSPI: if (ospi_done || ospi_error) begin done <= ospi_done; error <= ospi_error; active <= 1'b0; end
          default: begin active <= 1'b0; error <= 1'b1; end
        endcase
      end
    end
  end
endmodule
