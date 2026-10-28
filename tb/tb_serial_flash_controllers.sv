`timescale 1ns/1ps

module tb_serial_flash_controllers;
  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic [2:0] memory_type = 3'd0;
  logic [23:0] addr = 24'h12_3456;
  logic [15:0] length = 16'd32;
  logic read_req = 1'b0;
  logic busy, done, error;
  logic [31:0] read_data;

  logic spi_sclk, spi_cs_n, spi_mosi;
  logic miso = 1'b1;
  logic qspi_sclk, qspi_cs_n;
  tri [3:0] qspi_io;
  logic [3:0] qspi_drive;
  logic qspi_flash_oe = 1'b0;
  integer qspi_cycles = 0;
  logic [31:0] qspi_flash_word = 32'h1234_5678;
  logic ospi_sclk, ospi_cs_n;
  tri [7:0] ospi_io;
  logic [7:0] ospi_drive;
  logic ospi_flash_oe = 1'b0;
  integer ospi_cycles = 0;
  logic [31:0] ospi_flash_word = 32'h89AB_CDEF;

  integer timeout_count;

  always #5 clk = ~clk;

  always @(posedge clk) begin
    if (rst_n && (!spi_cs_n || !qspi_cs_n || !ospi_cs_n)) begin
      case (memory_type)
        3'd0: if (spi_cs_n || !qspi_cs_n || !ospi_cs_n)
          $fatal(1, "SPI transfer selected incorrect flash chip-selects");
        3'd1: if (qspi_cs_n || !spi_cs_n || !ospi_cs_n)
          $fatal(1, "QSPI transfer selected incorrect flash chip-selects");
        3'd2: if (ospi_cs_n || !spi_cs_n || !qspi_cs_n)
          $fatal(1, "OSPI transfer selected incorrect flash chip-selects");
        default: $fatal(1, "Unsupported memory type asserted a flash chip select");
      endcase
    end
  end

  assign qspi_io = qspi_flash_oe ? qspi_drive : 4'bz;
  assign ospi_io = ospi_flash_oe ? ospi_drive : 8'bz;

  always @(negedge qspi_cs_n)
    qspi_cycles = 0;

  always @(posedge qspi_sclk)
    if (!qspi_cs_n) qspi_cycles = qspi_cycles + 1;

  always_comb begin
    qspi_flash_oe = !qspi_cs_n && (qspi_cycles >= 16);
    if (qspi_cycles >= 16 && qspi_cycles < 24)
      qspi_drive = (qspi_flash_word >> ((7 - (qspi_cycles - 16)) * 4)) & 4'hF;
    else
      qspi_drive = 4'h0;
  end

  always @(negedge ospi_cs_n)
    ospi_cycles = 0;

  always @(posedge ospi_sclk)
    if (!ospi_cs_n) ospi_cycles = ospi_cycles + 1;

  always_comb begin
    ospi_flash_oe = !ospi_cs_n && (ospi_cycles >= 6);
    if (ospi_cycles >= 6 && ospi_cycles < 10)
      ospi_drive = (ospi_flash_word >> ((3 - (ospi_cycles - 6)) * 8)) & 8'hFF;
    else
      ospi_drive = 8'h00;
  end

  memory_manager #(
    .ADDR_WIDTH(24),
    .DATA_WIDTH(32),
    .MEM_TYPE_WIDTH(3),
    .CLK_FREQ_HZ(100_000_000),
    .SPI_CLK_FREQ_HZ(10_000_000),
    .QSPI_CLK_FREQ_HZ(10_000_000),
    .OSPI_CLK_FREQ_HZ(10_000_000),
    .QSPI_DUMMY_CYCLES(2),
    .OSPI_DUMMY_CYCLES(2)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .memory_type(memory_type),
    .addr(addr),
    .length(length),
    .read_req(read_req),
    .busy(busy),
    .done(done),
    .error(error),
    .read_data(read_data),
    .sclk(spi_sclk),
    .cs_n(spi_cs_n),
    .mosi(spi_mosi),
    .miso(miso),
    .qspi_sclk(qspi_sclk),
    .qspi_cs_n(qspi_cs_n),
    .qspi_io(qspi_io),
    .ospi_sclk(ospi_sclk),
    .ospi_cs_n(ospi_cs_n),
    .ospi_io(ospi_io)
  );

  task automatic start_read(input logic [2:0] selected_type);
    begin
      @(negedge clk);
      memory_type = selected_type;
      length = 16'd32;
      read_req = 1'b1;
      @(negedge clk);
      read_req = 1'b0;
    end
  endtask

  task automatic wait_for_result(input string controller_name);
    begin
      timeout_count = 0;
      while (!done && !error) begin
        @(posedge clk);
        timeout_count++;
        if (timeout_count > 1000)
          $fatal(1, "%s read timed out", controller_name);
      end
      #1;
      if (error) $fatal(1, "%s read unexpectedly failed", controller_name);
      if (busy) $fatal(1, "%s manager remained busy after completion", controller_name);
    end
  endtask

  task automatic test_spi_selection;
    begin
      start_read(3'd0);
      wait_for_result("SPI");
      if (read_data !== 32'hFFFF_FFFF)
        $fatal(1, "SPI data mismatch: expected FFFFFFFF got %08x", read_data);
      if (!spi_cs_n || !qspi_cs_n || !ospi_cs_n)
        $fatal(1, "SPI selection did not leave exactly the SPI chip select active");
      $display("PASS: manager selected SPI");
    end
  endtask

  task automatic test_qspi_selection;
    begin
      start_read(3'd1);
      wait_for_result("QSPI");
      if (read_data !== qspi_flash_word)
        $fatal(1, "QSPI data mismatch: expected %08x got %08x", qspi_flash_word, read_data);
      if (!spi_cs_n || !ospi_cs_n)
        $fatal(1, "QSPI selection incorrectly activated another flash");
      $display("PASS: manager selected QSPI");
    end
  endtask

  task automatic test_ospi_selection;
    begin
      start_read(3'd2);
      wait_for_result("OSPI");
      if (read_data !== ospi_flash_word)
        $fatal(1, "OSPI data mismatch: expected %08x got %08x", ospi_flash_word, read_data);
      if (!spi_cs_n || !qspi_cs_n)
        $fatal(1, "OSPI selection incorrectly activated another flash");
      $display("PASS: manager selected OSPI");
    end
  endtask

  task automatic test_invalid_selection;
    begin
      @(negedge clk);
      memory_type = 3'd7;
      read_req = 1'b1;
      @(posedge clk);
      #1;
      if (!error || busy)
        $fatal(1, "Unsupported memory type must report an error without starting a transfer");
      if (!spi_cs_n || !qspi_cs_n || !ospi_cs_n)
        $fatal(1, "Unsupported memory type selected a flash device");
      @(negedge clk);
      read_req = 1'b0;
      $display("PASS: invalid memory type rejected");
    end
  endtask

  task automatic test_invalid_qspi_length;
    begin
      @(negedge clk);
      memory_type = 3'd1;
      length = 16'd3;
      read_req = 1'b1;
      @(negedge clk);
      read_req = 1'b0;
      timeout_count = 0;
      while (!error) begin
        @(posedge clk);
        timeout_count++;
        if (timeout_count > 10) $fatal(1, "Unaligned QSPI transfer did not report error");
      end
      #1;
      if (busy) $fatal(1, "Invalid QSPI length left manager busy");
      length = 16'd32;
      $display("PASS: invalid QSPI length rejected");
    end
  endtask

  initial begin
    repeat (4) @(posedge clk);
    #1 rst_n = 1'b1;

    test_spi_selection();
    test_qspi_selection();
    test_ospi_selection();
    test_invalid_selection();
    test_invalid_qspi_length();

    $display("PASS: memory manager dispatch and flash controller checks passed");
    $finish;
  end
endmodule
