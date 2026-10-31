`timescale 1ns/1ps

// AXI4-Lite register aperture for the Memory, DMA, and JTAG control banks.
// All writes are single 32-bit register writes; AW and W are independently
// captured as required by AXI4-Lite. Peripheral control bits generate one-cycle
// pulses, while configuration/status registers remain readable.
module programmer_control_regs_axi #(
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

  output logic [2:0]  memory_type,
  output logic [31:0] memory_address,
  output logic [31:0] memory_length_bits,
  output logic        memory_start,
  output logic        memory_abort,
  input  logic        memory_busy,
  input  logic        memory_done,
  input  logic        memory_error,

  output logic [31:0] dma_source_address,
  output logic [31:0] dma_length_bits,
  output logic        dma_start,
  output logic        dma_abort,
  input  logic        dma_busy,
  input  logic        dma_done,
  input  logic        dma_error,

  output logic [31:0] jtag_ir_length,
  output logic [31:0] jtag_ir_opcode,
  output logic [31:0] jtag_dr_length,
  output logic [31:0] jtag_frequency,
  output logic [31:0] jtag_expected_idcode,
  output logic [7:0]  jtag_mode,
  output logic        jtag_start,
  output logic        jtag_scan_ir,
  output logic        jtag_capture_idcode,
  output logic        jtag_verify_idcode,
  output logic        jtag_abort,
  input  logic        jtag_done,
  input  logic        jtag_error,
  input  logic [31:0] jtag_idcode,
  output logic        write_access_error
);
  localparam logic [31:0] REG_MEM_CTRL   = 32'h0000_0000;
  localparam logic [31:0] REG_MEM_TYPE   = 32'h0000_0004;
  localparam logic [31:0] REG_MEM_ADDR   = 32'h0000_0008;
  localparam logic [31:0] REG_MEM_LENGTH = 32'h0000_000C;
  localparam logic [31:0] REG_MEM_STATUS = 32'h0000_0010;

  localparam logic [31:0] REG_DMA_CTRL   = 32'h0000_1000;
  localparam logic [31:0] REG_DMA_SOURCE = 32'h0000_1004;
  localparam logic [31:0] REG_DMA_LENGTH = 32'h0000_1008;
  localparam logic [31:0] REG_DMA_STATUS = 32'h0000_100C;

  localparam logic [31:0] REG_JTAG_CTRL  = 32'h0000_2000;
  localparam logic [31:0] REG_JTAG_IRLEN = 32'h0000_2004;
  localparam logic [31:0] REG_JTAG_DRLEN = 32'h0000_2008;
  localparam logic [31:0] REG_JTAG_FREQ  = 32'h0000_200C;
  localparam logic [31:0] REG_JTAG_IDCODE= 32'h0000_2010;
  localparam logic [31:0] REG_JTAG_IROP  = 32'h0000_2014;
  localparam logic [31:0] REG_JTAG_MODE = 32'h0000_2018;
  localparam logic [31:0] REG_JTAG_STATUS=32'h0000_201C;

  logic aw_hold_valid, w_hold_valid;
  logic [ADDR_WIDTH-1:0] aw_hold_addr;
  logic [DATA_WIDTH-1:0] w_hold_data;
  logic [DATA_WIDTH/8-1:0] w_hold_strb;
  logic write_have_addr, write_have_data, write_commit;
  logic [ADDR_WIDTH-1:0] write_addr_effective;
  logic [DATA_WIDTH-1:0] write_data_effective;
  logic [DATA_WIDTH/8-1:0] write_strb_effective;
  logic [31:0] read_mux;
  logic read_addr_valid, write_addr_valid;
  logic mem_done_sticky, mem_error_sticky;
  logic dma_done_sticky, dma_error_sticky;
  logic jtag_done_sticky, jtag_error_sticky;

  function automatic logic [31:0] merge_wstrb(
    input logic [31:0] old_value,
    input logic [31:0] new_value,
    input logic [3:0] strobe
  );
    logic [31:0] merged;
    merged = old_value;
    for (int b = 0; b < 4; b++)
      if (strobe[b]) merged[b*8 +: 8] = new_value[b*8 +: 8];
    return merged;
  endfunction

  always_comb begin
    s_awready = !aw_hold_valid && !s_bvalid;
    s_wready  = !w_hold_valid && !s_bvalid;
    s_arready = !s_rvalid;

    write_have_addr = aw_hold_valid || (s_awvalid && s_awready);
    write_have_data = w_hold_valid || (s_wvalid && s_wready);
    write_addr_effective = aw_hold_valid ? aw_hold_addr : s_awaddr;
    write_data_effective = w_hold_valid ? w_hold_data : s_wdata;
    write_strb_effective = w_hold_valid ? w_hold_strb : s_wstrb;
    write_commit = !s_bvalid && write_have_addr && write_have_data;

    read_mux = 32'h0000_0000;
    read_addr_valid = 1'b1;
    case (s_araddr)
      REG_MEM_CTRL:   read_mux = 32'h0;
      REG_MEM_TYPE:   read_mux = {29'd0, memory_type};
      REG_MEM_ADDR:   read_mux = memory_address;
      REG_MEM_LENGTH: read_mux = memory_length_bits;
      REG_MEM_STATUS: read_mux = {29'd0, mem_error_sticky, mem_done_sticky, memory_busy};
      REG_DMA_CTRL:   read_mux = 32'h0;
      REG_DMA_SOURCE: read_mux = dma_source_address;
      REG_DMA_LENGTH: read_mux = dma_length_bits;
      REG_DMA_STATUS: read_mux = {29'd0, dma_error_sticky, dma_done_sticky, dma_busy};
      REG_JTAG_CTRL:  read_mux = 32'h0;
      REG_JTAG_IRLEN: read_mux = jtag_ir_length;
      REG_JTAG_IROP:  read_mux = jtag_ir_opcode;
      REG_JTAG_DRLEN: read_mux = jtag_dr_length;
      REG_JTAG_FREQ:  read_mux = jtag_frequency;
      REG_JTAG_IDCODE:read_mux = jtag_expected_idcode;
      REG_JTAG_MODE:  read_mux = {24'd0, jtag_mode};
      REG_JTAG_STATUS:read_mux = {jtag_idcode[15:0], 14'd0, jtag_error_sticky, jtag_done_sticky};
      default: begin read_mux = 32'h0; read_addr_valid = 1'b0; end
    endcase

    write_addr_valid = 1'b1;
    case (write_addr_effective)
      REG_MEM_CTRL, REG_MEM_TYPE, REG_MEM_ADDR, REG_MEM_LENGTH,
      REG_DMA_CTRL, REG_DMA_SOURCE, REG_DMA_LENGTH,
      REG_JTAG_CTRL, REG_JTAG_IRLEN, REG_JTAG_DRLEN,
      REG_JTAG_FREQ, REG_JTAG_IDCODE, REG_JTAG_IROP, REG_JTAG_MODE: write_addr_valid = 1'b1;
      default: write_addr_valid = 1'b0;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      aw_hold_valid <= 1'b0;
      w_hold_valid <= 1'b0;
      aw_hold_addr <= '0;
      w_hold_data <= '0;
      w_hold_strb <= '0;
      s_bvalid <= 1'b0;
      s_bresp <= 2'b00;
      s_rvalid <= 1'b0;
      s_rdata <= '0;
      s_rresp <= 2'b00;

      memory_type <= 3'd0;
      memory_address <= '0;
      memory_length_bits <= '0;
      memory_start <= 1'b0;
      memory_abort <= 1'b0;
      dma_source_address <= '0;
      dma_length_bits <= '0;
      dma_start <= 1'b0;
      dma_abort <= 1'b0;
      jtag_ir_length <= 32'd4;
      jtag_ir_opcode <= 32'd1;
      jtag_dr_length <= 32'd32;
      jtag_frequency <= 32'd100_000;
      jtag_expected_idcode <= '0;
      jtag_mode <= '0;
      jtag_start <= 1'b0;
      jtag_scan_ir <= 1'b0;
      jtag_capture_idcode <= 1'b0;
      jtag_verify_idcode <= 1'b0;
      jtag_abort <= 1'b0;
      mem_done_sticky <= 1'b0;
      mem_error_sticky <= 1'b0;
      dma_done_sticky <= 1'b0;
      dma_error_sticky <= 1'b0;
      jtag_done_sticky <= 1'b0;
      jtag_error_sticky <= 1'b0;
      write_access_error <= 1'b0;
    end else begin
      memory_start <= 1'b0;
      memory_abort <= 1'b0;
      dma_start <= 1'b0;
      dma_abort <= 1'b0;
      jtag_start <= 1'b0;
      jtag_scan_ir <= 1'b0;
      jtag_capture_idcode <= 1'b0;
      jtag_verify_idcode <= 1'b0;
      jtag_abort <= 1'b0;

      if (memory_start) begin mem_done_sticky <= 1'b0; mem_error_sticky <= 1'b0; end
      if (memory_done) mem_done_sticky <= 1'b1;
      if (memory_error) mem_error_sticky <= 1'b1;
      if (dma_start) begin dma_done_sticky <= 1'b0; dma_error_sticky <= 1'b0; end
      if (dma_done) dma_done_sticky <= 1'b1;
      if (dma_error) dma_error_sticky <= 1'b1;
      if (jtag_start) begin jtag_done_sticky <= 1'b0; jtag_error_sticky <= 1'b0; end
      if (jtag_done) jtag_done_sticky <= 1'b1;
      if (jtag_error) jtag_error_sticky <= 1'b1;

      if (s_awvalid && s_awready) begin
        aw_hold_valid <= 1'b1;
        aw_hold_addr <= s_awaddr;
      end
      if (s_wvalid && s_wready) begin
        w_hold_valid <= 1'b1;
        w_hold_data <= s_wdata;
        w_hold_strb <= s_wstrb;
      end

      if (write_commit) begin
        aw_hold_valid <= 1'b0;
        w_hold_valid <= 1'b0;
        s_bvalid <= 1'b1;
        s_bresp <= write_addr_valid ? 2'b00 : 2'b10;
        if (write_addr_valid) begin
          case (write_addr_effective)
            REG_MEM_CTRL: if (write_strb_effective[0]) begin
              memory_start <= write_data_effective[0];
              memory_abort <= write_data_effective[1];
            end
            REG_MEM_TYPE: if (write_strb_effective[0]) memory_type <= write_data_effective[2:0];
            REG_MEM_ADDR: memory_address <= merge_wstrb(memory_address, write_data_effective, write_strb_effective);
            REG_MEM_LENGTH: memory_length_bits <= merge_wstrb(memory_length_bits, write_data_effective, write_strb_effective);
            REG_DMA_CTRL: if (write_strb_effective[0]) begin
              dma_start <= write_data_effective[0];
              dma_abort <= write_data_effective[1];
            end
            REG_DMA_SOURCE: dma_source_address <= merge_wstrb(dma_source_address, write_data_effective, write_strb_effective);
            REG_DMA_LENGTH: dma_length_bits <= merge_wstrb(dma_length_bits, write_data_effective, write_strb_effective);
            REG_JTAG_CTRL: if (write_strb_effective[0]) begin
              jtag_start <= write_data_effective[0];
              jtag_scan_ir <= write_data_effective[1];
              jtag_capture_idcode <= write_data_effective[2];
              jtag_verify_idcode <= write_data_effective[3];
              jtag_abort <= write_data_effective[4];
            end
            REG_JTAG_IRLEN: jtag_ir_length <= merge_wstrb(jtag_ir_length, write_data_effective, write_strb_effective);
            REG_JTAG_IROP:  jtag_ir_opcode <= merge_wstrb(jtag_ir_opcode, write_data_effective, write_strb_effective);
            REG_JTAG_DRLEN: jtag_dr_length <= merge_wstrb(jtag_dr_length, write_data_effective, write_strb_effective);
            REG_JTAG_FREQ: jtag_frequency <= merge_wstrb(jtag_frequency, write_data_effective, write_strb_effective);
            REG_JTAG_IDCODE: jtag_expected_idcode <= merge_wstrb(jtag_expected_idcode, write_data_effective, write_strb_effective);
            REG_JTAG_MODE: if (write_strb_effective[0]) jtag_mode <= write_data_effective[7:0];
            default: write_access_error <= 1'b1;
          endcase
        end else begin
          write_access_error <= 1'b1;
        end
      end else if (s_bvalid && s_bready) begin
        s_bvalid <= 1'b0;
      end

      if (s_arvalid && s_arready) begin
        s_rvalid <= 1'b1;
        s_rdata <= read_mux;
        s_rresp <= read_addr_valid ? 2'b00 : 2'b10;
      end else if (s_rvalid && s_rready) begin
        s_rvalid <= 1'b0;
      end
    end
  end
endmodule
