`timescale 1ns/1ps

module programmer_regs #(
  parameter int ADDR_WIDTH = 32,
  parameter int DATA_WIDTH = 32
)(
  input  logic clk,
  input  logic rst_n,
  input  logic [ADDR_WIDTH-1:0] awaddr,
  input  logic awvalid,
  output logic awready,
  input  logic [DATA_WIDTH-1:0] wdata,
  input  logic [DATA_WIDTH/8-1:0] wstrb,
  input  logic wvalid,
  output logic wready,
  output logic [1:0] bresp,
  output logic bvalid,
  input  logic bready,
  input  logic [ADDR_WIDTH-1:0] araddr,
  input  logic arvalid,
  output logic arready,
  output logic [DATA_WIDTH-1:0] rdata,
  output logic [1:0] rresp,
  output logic rvalid,
  input  logic rready,
  output logic config_valid,
  output programmer_pkg::programmer_config_t cfg,
  output logic [31:0] status_reg,
  output logic [31:0] error_reg,
  input  logic [31:0] idcode_value
);
  // Purpose: register bank for controller configuration and status.
  // Inputs: clk, rst_n, axi_if, idcode_value
  // Outputs: config_valid, cfg, status_reg, error_reg
  // Clock/reset: clk, rst_n
  // Assumption: a minimal register map is implemented for controller programming.

  localparam int REG_CONTROL = 32'h00;
  localparam int REG_STATUS = 32'h04;
  localparam int REG_ERROR = 32'h08;
  localparam int REG_CFG0 = 32'h10;
  localparam int REG_CFG1 = 32'h14;
  localparam int REG_CFG2 = 32'h18;
  localparam int REG_IDCODE = 32'h1C;

  logic [DATA_WIDTH-1:0] regs [0:31];
  logic [ADDR_WIDTH-1:0] write_addr_q;
  logic [DATA_WIDTH-1:0] write_data_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < 32; i++) regs[i] <= '0;
      config_valid <= 1'b0;
      cfg <= '0;
      status_reg <= '0;
      error_reg <= '0;
    end else begin
      if (awvalid && awready) begin
        write_addr_q <= awaddr;
        write_data_q <= wdata;
      end

      if (wvalid && wready) begin
        case (awaddr)
          REG_CONTROL: regs[0] <= wdata;
          REG_STATUS:  regs[1] <= wdata;
          REG_ERROR:   regs[2] <= wdata;
          REG_CFG0:    regs[3] <= wdata;
          REG_CFG1:    regs[4] <= wdata;
          REG_CFG2:    regs[5] <= wdata;
          default: ;
        endcase
      end

      if (arvalid && arready) begin
        case (araddr)
          REG_CONTROL: rdata <= regs[0];
          REG_STATUS:  rdata <= regs[1];
          REG_ERROR:   rdata <= regs[2];
          REG_CFG0:    rdata <= regs[3];
          REG_CFG1:    rdata <= regs[4];
          REG_CFG2:    rdata <= regs[5];
          REG_IDCODE:  rdata <= idcode_value;
          default:     rdata <= '0;
        endcase
      end

      config_valid <= (regs[0][0] == 1'b1);
      cfg.memory_type <= regs[3][2:0];
      cfg.memory_address <= regs[3][31:0];
      cfg.bitstream_length <= regs[4];
      cfg.expected_idcode <= regs[5];
      cfg.jtag_frequency <= regs[6];
      status_reg <= regs[1];
      error_reg <= regs[2];
    end
  end

  always_comb begin
    awready = 1'b1;
    wready = 1'b1;
    bvalid = awvalid && wvalid;
    bresp = 2'b00;
    arready = 1'b1;
    rvalid = arvalid;
    rresp = 2'b00;
  end
endmodule
