`timescale 1ns/1ps

// Single-outstanding AXI4-Lite write master used by the autonomous scheduler.
// AW and W are accepted independently; B is consumed only after both handshakes.
module axi_lite_write_master #(
  parameter int ADDR_WIDTH = 32,
  parameter int DATA_WIDTH = 32
)(
  input  logic clk,
  input  logic rst_n,
  input  logic req_valid,
  output logic req_ready,
  input  logic [ADDR_WIDTH-1:0] req_addr,
  input  logic [DATA_WIDTH-1:0] req_data,
  output logic done,
  output logic error,
  output logic [ADDR_WIDTH-1:0] m_awaddr,
  output logic m_awvalid,
  input  logic m_awready,
  output logic [DATA_WIDTH-1:0] m_wdata,
  output logic [DATA_WIDTH/8-1:0] m_wstrb,
  output logic m_wvalid,
  input  logic m_wready,
  input  logic [1:0] m_bresp,
  input  logic m_bvalid,
  output logic m_bready
);
  typedef enum logic [1:0] {W_IDLE, W_SEND, W_RESP} write_state_t;
  write_state_t state;
  logic aw_seen, w_seen;

  assign req_ready = (state == W_IDLE);
  assign m_awvalid = (state == W_SEND) && !aw_seen;
  assign m_wvalid  = (state == W_SEND) && !w_seen;
  assign m_bready  = (state == W_RESP);
  assign m_wstrb   = '1;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state      <= W_IDLE;
      m_awaddr   <= '0;
      m_wdata    <= '0;
      aw_seen    <= 1'b0;
      w_seen     <= 1'b0;
      done       <= 1'b0;
      error      <= 1'b0;
    end else begin
      done  <= 1'b0;
      error <= 1'b0;
      case (state)
        W_IDLE: begin
          aw_seen <= 1'b0;
          w_seen  <= 1'b0;
          if (req_valid) begin
            m_awaddr <= req_addr;
            m_wdata  <= req_data;
            state    <= W_SEND;
          end
        end
        W_SEND: begin
          if (m_awvalid && m_awready) aw_seen <= 1'b1;
          if (m_wvalid  && m_wready)  w_seen  <= 1'b1;
          if ((aw_seen || (m_awvalid && m_awready)) &&
              (w_seen  || (m_wvalid  && m_wready)))
            state <= W_RESP;
        end
        W_RESP: begin
          if (m_bvalid && m_bready) begin
            done  <= 1'b1;
            error <= (m_bresp != 2'b00);
            state <= W_IDLE;
          end
        end
        default: begin
          state <= W_IDLE;
          error <= 1'b1;
        end
      endcase
    end
  end
endmodule
