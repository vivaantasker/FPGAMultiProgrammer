`timescale 1ns/1ps

module axi_lite_interconnect #(
  parameter int NUM_SLAVES = 4,
  parameter int ADDR_WIDTH = 32,
  parameter int DATA_WIDTH = 32
)(
  input  logic clk,
  input  logic rst_n,
  input  logic [ADDR_WIDTH-1:0] s_awaddr,
  input  logic s_awvalid,
  output logic s_awready,
  input  logic [DATA_WIDTH-1:0] s_wdata,
  input  logic [DATA_WIDTH/8-1:0] s_wstrb,
  input  logic s_wvalid,
  output logic s_wready,
  output logic [1:0] s_bresp,
  output logic s_bvalid,
  input  logic s_bready,
  input  logic [ADDR_WIDTH-1:0] s_araddr,
  input  logic s_arvalid,
  output logic s_arready,
  output logic [DATA_WIDTH-1:0] s_rdata,
  output logic [1:0] s_rresp,
  output logic s_rvalid,
  input  logic s_rready,
  output logic [NUM_SLAVES-1:0] m_awvalid,
  input  logic [NUM_SLAVES-1:0] m_awready,
  output logic [NUM_SLAVES-1:0] m_wvalid,
  input  logic [NUM_SLAVES-1:0] m_wready,
  input  logic [NUM_SLAVES*2-1:0] m_bresp,
  input  logic [NUM_SLAVES-1:0] m_bvalid,
  output logic [NUM_SLAVES-1:0] m_bready,
  output logic [NUM_SLAVES-1:0] m_arvalid,
  input  logic [NUM_SLAVES-1:0] m_arready,
  input  logic [NUM_SLAVES*DATA_WIDTH-1:0] m_rdata,
  input  logic [NUM_SLAVES*2-1:0] m_rresp,
  input  logic [NUM_SLAVES-1:0] m_rvalid,
  output logic [NUM_SLAVES-1:0] m_rready,
  input  logic [NUM_SLAVES-1:0] sel
);
  // Purpose: single-master, multi-slave AXI-Lite interconnect.
  // Inputs: clk, rst_n, master request channels, slave selection
  // Outputs: routed requests and response data to and from selected slave.
  // Clock/reset: clk, rst_n
  // Assumption: addresses are statically decoded into a single selected slave.

  logic [NUM_SLAVES-1:0] aw_active;
  logic [NUM_SLAVES-1:0] ar_active;

  always_comb begin
    aw_active = '0;
    ar_active = '0;
    aw_active[sel] = s_awvalid;
    ar_active[sel] = s_arvalid;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s_awready <= 1'b0; s_wready <= 1'b0; s_bvalid <= 1'b0; s_arready <= 1'b0; s_rvalid <= 1'b0;
      s_rdata <= '0; s_rresp <= 2'b00; s_bresp <= 2'b00;
    end else begin
      s_awready <= m_awready[sel];
      s_wready <= m_wready[sel];
      s_arready <= m_arready[sel];
      s_bvalid <= m_bvalid[sel];
      s_bresp <= m_bresp[sel*2 +: 2];
      s_rvalid <= m_rvalid[sel];
      s_rdata <= m_rdata[sel*DATA_WIDTH +: DATA_WIDTH];
      s_rresp <= m_rresp[sel*2 +: 2];
      m_awvalid <= aw_active;
      m_wvalid <= aw_active;
      m_bready <= {NUM_SLAVES{1'b0}};
      m_bready[sel] <= s_bready;
      m_arvalid <= ar_active;
      m_rready <= {NUM_SLAVES{1'b0}};
      m_rready[sel] <= s_rready;
    end
  end
endmodule
