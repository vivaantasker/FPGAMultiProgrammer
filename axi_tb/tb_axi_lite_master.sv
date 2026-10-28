`timescale 1ns/1ps

module tb_axi_lite_master;
  import axi_env_pkg::*;

  logic clk = 1'b0;
  axi_lite_if bus(clk);
  axi_environment env;

  always #5 clk = ~clk;

  axi_lite_master #(.ADDR_WIDTH(32), .DATA_WIDTH(32)) dut (
    .clk(clk), .rst_n(bus.rst_n),
    .awaddr(bus.awaddr), .awvalid(bus.awvalid), .awready(bus.awready),
    .wdata(bus.wdata), .wstrb(bus.wstrb), .wvalid(bus.wvalid), .wready(bus.wready),
    .bresp(bus.bresp), .bvalid(bus.bvalid), .bready(bus.bready),
    .araddr(bus.araddr), .arvalid(bus.arvalid), .arready(bus.arready),
    .rdata(bus.rdata), .rresp(bus.rresp), .rvalid(bus.rvalid), .rready(bus.rready),
    .read_data(bus.read_data), .read_valid(bus.read_valid),
    .write_data(bus.write_data), .write_req(bus.write_req), .read_req(bus.read_req),
    .write_addr(bus.write_addr), .read_addr(bus.read_addr)
  );

  initial begin
    bus.rst_n = 0;
    bus.awready = 0;
    bus.wready = 0;
    bus.bresp = 0;
    bus.bvalid = 0;
    bus.arready = 0;
    bus.rdata = 0;
    bus.rresp = 0;
    bus.rvalid = 0;
    bus.write_data = 0;
    bus.write_req = 0;
    bus.read_req = 0;
    bus.write_addr = 0;
    bus.read_addr = 0;
    repeat (4) @(posedge clk);
    @(negedge clk);
    bus.rst_n = 1;
    env = new(bus, 40);
    env.run();
    $display("AXI-Lite test PASS");
    $finish;
  end
endmodule
