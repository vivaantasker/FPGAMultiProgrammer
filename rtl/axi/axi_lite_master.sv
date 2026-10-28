`timescale 1ns/1ps

module axi_lite_master #(
  parameter int ADDR_WIDTH = 32,
  parameter int DATA_WIDTH = 32
)(
  input  logic clk,
  input  logic rst_n,
  output logic [ADDR_WIDTH-1:0] awaddr,
  output logic awvalid,
  input  logic awready,
  output logic [DATA_WIDTH-1:0] wdata,
  output logic [DATA_WIDTH/8-1:0] wstrb,
  output logic wvalid,
  input  logic wready,
  input  logic [1:0] bresp,
  input  logic bvalid,
  output logic bready,
  output logic [ADDR_WIDTH-1:0] araddr,
  output logic arvalid,
  input  logic arready,
  input  logic [DATA_WIDTH-1:0] rdata,
  input  logic [1:0] rresp,
  input  logic rvalid,
  output logic rready,
  output logic [DATA_WIDTH-1:0] read_data,
  output logic read_valid,
  input  logic [DATA_WIDTH-1:0] write_data,
  input  logic write_req,
  input  logic read_req,
  input  logic [ADDR_WIDTH-1:0] write_addr,
  input  logic [ADDR_WIDTH-1:0] read_addr
);
  // Purpose: simple AXI-Lite master wrapper for register access.
  // Inputs: clk, rst_n, write_req, read_req, write_addr, read_addr, write_data
  // Outputs: awaddr, awvalid, wdata, wvalid, bready, araddr, arvalid, rready, read_data, read_valid
  // Clock/reset: clk, rst_n
  // Assumption: one outstanding transaction at a time; no burst support.

  typedef enum logic [1:0] { IDLE, WRITE, READ } state_t;
  state_t state;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      awaddr <= '0; awvalid <= 1'b0; wdata <= '0; wstrb <= '1; wvalid <= 1'b0; bready <= 1'b0;
      araddr <= '0; arvalid <= 1'b0; rready <= 1'b0; read_data <= '0; read_valid <= 1'b0; state <= IDLE;
    end else begin
      case (state)
        IDLE: begin
          read_valid <= 1'b0;
          if (write_req) begin
            awaddr <= write_addr; awvalid <= 1'b1; wdata <= write_data; wstrb <= '1; wvalid <= 1'b1; bready <= 1'b1; state <= WRITE;
          end else if (read_req) begin
            araddr <= read_addr; arvalid <= 1'b1; rready <= 1'b1; state <= READ;
          end
        end
        WRITE: begin
          if (awvalid && awready) awvalid <= 1'b0;
          if (wvalid && wready) wvalid <= 1'b0;
          if (bvalid && bready) begin
            bready <= 1'b0; state <= IDLE;
          end
        end
        READ: begin
          if (arvalid && arready) arvalid <= 1'b0;
          if (rvalid && rready) begin
            read_data <= rdata;
            read_valid <= 1'b1;
            rready <= 1'b0;
            state <= IDLE;
          end
        end
        default: state <= IDLE;
      endcase
    end
  end
endmodule
