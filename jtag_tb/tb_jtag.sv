`timescale 1ns/1ps

module tb_jtag;
  import jtag_env_pkg::*;

  logic clk = 1'b0;
  jtag_if bus(clk);
  jtag_environment env;

  always #5 clk = ~clk;

  jtag_tap u_tap (
    .clk(clk), .rst_n(bus.rst_n), .tms(bus.tms), .tdi(bus.tdi),
    .tdo(bus.tdo), .tap_state(bus.tap_state)
  );

  jtag_shift_engine #(.DATA_WIDTH(32)) u_shift (
    .clk(clk), .rst_n(bus.rst_n), .shift_enable(bus.shift_enable),
    .tdi_word(bus.tdi_word), .tdo_word(bus.tdo_word),
    .shift_tdi(bus.shift_tdi), .shift_tdo(bus.shift_tdo)
  );

  jtag_clock #(.CLK_FREQ_HZ(100_000_000)) u_clock (
    .clk(clk), .rst_n(bus.rst_n), .jtag_frequency(bus.jtag_frequency), .tck(bus.tck)
  );

  initial begin
    bus.rst_n = 0;
    bus.tms = 0;
    bus.tdi = 0;
    bus.shift_enable = 0;
    bus.tdi_word = 0;
    bus.tdo_word = 0;
    bus.jtag_frequency = 32'd10_000_000;
    repeat (4) @(posedge clk);
    #1;
    bus.rst_n = 1;
    env = new(bus);
    env.run();
    $display("JTAG test PASS");
    $finish;
  end
endmodule
