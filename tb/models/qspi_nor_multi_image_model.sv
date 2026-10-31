`timescale 1ns/1ps

// Pin-level behavioral QSPI NOR model for the generic SDR quad-read engine.
// Device profile: 0xEB read opcode, 24-bit address, two dummy clocks, low
// nibble first, then high nibble. This is a simulation profile, not a claim
// about any particular commercial flash part.
module qspi_nor_multi_image_model #(
  parameter int FLASH_BYTES = 262144,
  parameter int DUMMY_CYCLES = 2,
  parameter int NUM_IMAGES = 3,
  parameter bit INVALID_METADATA = 1'b0
)(
  input  logic cs_n,
  input  logic sclk,
  inout  wire [3:0] io
);
  logic [7:0] flash [0:FLASH_BYTES-1];
  logic [3:0] drive_value;
  logic drive_enable;
  logic [7:0] opcode_shift;
  logic [7:0] last_opcode;
  logic [23:0] address_shift;
  logic [23:0] last_address;
  integer command_bits;
  integer address_nibbles;
  integer dummy_count;
  integer data_nibbles;
  integer read_transactions;
  integer read_log_count;
  logic [23:0] read_address_log [0:15];
  logic [7:0] read_opcode_log [0:15];

  assign io = drive_enable ? drive_value : 4'bzzzz;

  task automatic put_word_le(input integer byte_addr, input logic [31:0] word_value);
    begin
      flash[byte_addr+0] = word_value[7:0];
      flash[byte_addr+1] = word_value[15:8];
      flash[byte_addr+2] = word_value[23:16];
      flash[byte_addr+3] = word_value[31:24];
    end
  endtask

  initial begin : init_flash
    for (int i = 0; i < FLASH_BYTES; i++) flash[i] = 8'hFF;

    // Metadata at address zero follows fpga_schedule_entry_t field order:
    // {flash_byte_offset, bitstream_size_bits, expected_idcode, duration_ms}.
    put_word_le(0, 32'h0000_1000); put_word_le(4, 32'd72);
    put_word_le(8, 32'h1234_5678); put_word_le(12, 32'd100);
    put_word_le(16, 32'h0001_0000); put_word_le(20, 32'd72);
    put_word_le(24, 32'h1234_5678); put_word_le(28, 32'd100);
    put_word_le(32, 32'h0002_0000); put_word_le(36, 32'd72);
    put_word_le(40, 32'h1234_5678); put_word_le(44, 32'd100);
    if (INVALID_METADATA) put_word_le(4, 32'd0); // Negative-test hook: zero length.

    // Three distinct nine-byte bitstreams. Stream data is sent LSB-first to JTAG.
    // Use 32-bit address constants: 16'h10000 and 16'h20000 overflow a
    // 16-bit literal and silently truncate to address zero, corrupting metadata.
    flash[32'h0000_1000+0] = 8'h11; flash[32'h0000_1000+1] = 8'h22;
    flash[32'h0000_1000+2] = 8'h33; flash[32'h0000_1000+3] = 8'h44;
    flash[32'h0000_1000+4] = 8'h55; flash[32'h0000_1000+5] = 8'h66;
    flash[32'h0000_1000+6] = 8'h77; flash[32'h0000_1000+7] = 8'h88;
    flash[32'h0000_1000+8] = 8'h99;

    flash[32'h0001_0000+0] = 8'hAA; flash[32'h0001_0000+1] = 8'hBB;
    flash[32'h0001_0000+2] = 8'hCC; flash[32'h0001_0000+3] = 8'hDD;
    flash[32'h0001_0000+4] = 8'hEE; flash[32'h0001_0000+5] = 8'h12;
    flash[32'h0001_0000+6] = 8'h34; flash[32'h0001_0000+7] = 8'h56;
    flash[32'h0001_0000+8] = 8'h78;

    flash[32'h0002_0000+0] = 8'hDE; flash[32'h0002_0000+1] = 8'hAD;
    flash[32'h0002_0000+2] = 8'hBE; flash[32'h0002_0000+3] = 8'hEF;
    flash[32'h0002_0000+4] = 8'hCA; flash[32'h0002_0000+5] = 8'hFE;
    flash[32'h0002_0000+6] = 8'h00; flash[32'h0002_0000+7] = 8'h01;
    flash[32'h0002_0000+8] = 8'h02;
  end

  // Count transactions when chip select is asserted. Parser state is reset on
  // the following chip-select deassertion in the SCLK edge process below.
  always @(negedge cs_n) begin
    read_transactions = read_transactions + 1;
  end

  initial begin
    read_transactions = 0;
    read_log_count = 0;
    command_bits = 0;
    address_nibbles = 0;
    dummy_count = 0;
    data_nibbles = 0;
    opcode_shift = 0;
    address_shift = 0;
    last_opcode = 0;
    last_address = 0;
    drive_enable = 0;
    drive_value = 0;
  end

  // Host samples command/address and consumes a data nibble on each QSPI rising edge.
  always @(posedge sclk or posedge cs_n) begin
    if (cs_n) begin
      command_bits <= 0;
      address_nibbles <= 0;
      dummy_count <= 0;
      data_nibbles <= 0;
      opcode_shift <= 0;
      address_shift <= 0;
      last_opcode <= 0;
      last_address <= 0;
    end else begin
      if (command_bits < 8) begin
        opcode_shift <= {opcode_shift[6:0], io[0]};
        command_bits <= command_bits + 1;
        if (command_bits == 7) last_opcode <= {opcode_shift[6:0], io[0]};
      end else if (address_nibbles < 6) begin
        address_shift <= {address_shift[19:0], io[3:0]};
        address_nibbles <= address_nibbles + 1;
        if (address_nibbles == 5) begin
          last_address <= {address_shift[19:0], io[3:0]};
          if (read_log_count < 16) begin
            read_address_log[read_log_count] <= {address_shift[19:0], io[3:0]};
            read_opcode_log[read_log_count] <= last_opcode;
            read_log_count <= read_log_count + 1;
          end
        end
      end else if (dummy_count < DUMMY_CYCLES) begin
        dummy_count <= dummy_count + 1;
      end else begin
        data_nibbles <= data_nibbles + 1;
      end
    end
  end

  // Flash drives each nibble after the falling SCLK edge. It releases the bus
  // during opcode/address phases and drives only the QSPI data phase.
  always @(negedge sclk or posedge cs_n) begin
    if (cs_n) begin
      drive_enable <= 1'b0;
      drive_value <= 4'h0;
    end else if ((command_bits >= 8) && (address_nibbles >= 6) &&
                 (dummy_count >= DUMMY_CYCLES)) begin
      drive_enable <= 1'b1;
      if ((last_address + (data_nibbles / 2)) < FLASH_BYTES) begin
        if (data_nibbles[0])
          drive_value <= flash[last_address + (data_nibbles / 2)][7:4];
        else
          drive_value <= flash[last_address + (data_nibbles / 2)][3:0];
      end else begin
        drive_value <= 4'hF;
      end
    end else begin
      drive_enable <= 1'b0;
      drive_value <= 4'h0;
    end
  end
endmodule
