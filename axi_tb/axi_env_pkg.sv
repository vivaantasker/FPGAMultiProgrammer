`timescale 1ns/1ps

package axi_env_pkg;
  class axi_transaction;
    int unsigned transaction_id;
    bit is_write;
    logic [31:0] address;
    logic [31:0] data;
    logic [1:0] response;

    function new();
      transaction_id = 0;
      is_write = 0;
      address = 0;
      data = 0;
      response = 0;
    endfunction
  endclass

  class axi_generator;
    mailbox #(axi_transaction) to_driver;
    mailbox #(axi_transaction) expected;
    logic [31:0] lfsr;

    function new(mailbox #(axi_transaction) driver_mbx,
                 mailbox #(axi_transaction) expected_mbx);
      to_driver = driver_mbx;
      expected = expected_mbx;
      lfsr = 32'hC001_D00D;
    endfunction

    task automatic emit(int unsigned id, bit is_write,
                        logic [31:0] address, logic [31:0] data);
      axi_transaction req;
      axi_transaction exp;
      req = new();
      exp = new();
      req.transaction_id = id;
      req.is_write = is_write;
      req.address = address;
      req.data = data;
      exp.transaction_id = id;
      exp.is_write = is_write;
      exp.address = address;
      exp.data = data;
      expected.put(exp);
      to_driver.put(req);
    endtask

    task run(int unsigned count);
      logic [31:0] address;
      for (int unsigned id = 0; id < count; id++) begin
        lfsr = {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
        address = {24'h0, lfsr[7:2], 2'b00};
        if ((id % 2) == 0)
          emit(id, 1, address, lfsr ^ (32'h9E37_79B9 * id));
        else
          emit(id, 0, address, 32'hA5C3_0000 ^ address);
      end
    endtask
  endclass

  class axi_driver;
    virtual axi_lite_if vif;
    mailbox #(axi_transaction) requests;

    function new(virtual axi_lite_if vif, mailbox #(axi_transaction) requests);
      this.vif = vif;
      this.requests = requests;
    endfunction

    task run(int unsigned count);
      axi_transaction req;
      initialize();
      wait (vif.rst_n === 1'b1);
      repeat (count) begin
        requests.get(req);
        if (req.is_write) drive_write(req);
        else drive_read(req);
      end
    endtask

    task initialize();
      vif.awready = 0;
      vif.wready = 0;
      vif.bresp = 0;
      vif.bvalid = 0;
      vif.arready = 0;
      vif.rdata = 0;
      vif.rresp = 0;
      vif.rvalid = 0;
      vif.write_req = 0;
      vif.read_req = 0;
      vif.write_addr = 0;
      vif.read_addr = 0;
      vif.write_data = 0;
    endtask

    task drive_write(axi_transaction req);
      bit aw_done;
      bit w_done;
      int unsigned cycle;
      aw_done = 0;
      w_done = 0;
      cycle = 0;
      @(negedge vif.clk);
      vif.write_addr = req.address;
      vif.write_data = req.data;
      vif.write_req = 1;
      @(negedge vif.clk);
      vif.write_req = 0;

      while (!(aw_done && w_done)) begin
        cycle++;
        if (cycle > 100) $fatal(1, "AXI driver timeout on AW/W for transaction %0d", req.transaction_id);
        case (req.transaction_id % 4)
          0: begin vif.awready = (cycle > 3); vif.wready = 1; end
          1: begin vif.awready = 1; vif.wready = (cycle > 4); end
          2: begin vif.awready = 1; vif.wready = (cycle > 3); end
          default: begin vif.awready = (cycle % 2 == 0); vif.wready = (cycle % 3 == 0); end
        endcase
        @(posedge vif.clk);
        if (vif.awvalid && vif.awready) aw_done = 1;
        if (vif.wvalid && vif.wready) w_done = 1;
        @(negedge vif.clk);
      end

      vif.awready = 0;
      vif.wready = 0;
      repeat (req.transaction_id % 3) @(negedge vif.clk);
      vif.bresp = 2'b00;
      vif.bvalid = 1;
      cycle = 0;
      while (!vif.bready) begin
        @(posedge vif.clk);
        cycle++;
        if (cycle > 10) $fatal(1, "AXI driver timeout waiting for BREADY");
      end
      @(negedge vif.clk);
      vif.bvalid = 0;
    endtask

    task drive_read(axi_transaction req);
      int unsigned cycle;
      logic [31:0] expected_data;
      cycle = 0;
      expected_data = 32'hA5C3_0000 ^ req.address;
      @(negedge vif.clk);
      vif.read_addr = req.address;
      vif.read_req = 1;
      @(negedge vif.clk);
      vif.read_req = 0;

      while (1) begin
        cycle++;
        if (cycle > 100) $fatal(1, "AXI driver timeout on AR for transaction %0d", req.transaction_id);
        vif.arready = (cycle > 2) && ((cycle + req.transaction_id) % 4 != 1);
        @(posedge vif.clk);
        if (vif.arvalid && vif.arready) break;
      end

      @(negedge vif.clk);
      vif.arready = 0;
      repeat (req.transaction_id % 3) @(negedge vif.clk);
      vif.rdata = expected_data;
      vif.rresp = 2'b00;
      vif.rvalid = 1;
      cycle = 0;
      while (!vif.rready) begin
        @(posedge vif.clk);
        cycle++;
        if (cycle > 10) $fatal(1, "AXI driver timeout waiting for RREADY");
      end
      @(posedge vif.clk);
      #1;
      if (vif.read_valid !== 1'b1)
        $fatal(1, "AXI read_valid missing for transaction %0d", req.transaction_id);
      if (vif.read_data !== expected_data)
        $fatal(1, "AXI read-data mismatch for transaction %0d", req.transaction_id);
      @(negedge vif.clk);
      vif.rvalid = 0;
    endtask
  endclass

  class axi_monitor;
    virtual axi_lite_if vif;
    mailbox #(axi_transaction) observed;
    bit aw_seen;
    bit w_seen;
    logic [31:0] saved_awaddr;
    logic [31:0] saved_wdata;
    logic [31:0] saved_araddr;
    bit previous_aw_stall;
    bit previous_w_stall;
    bit previous_ar_stall;
    logic [31:0] previous_awaddr;
    logic [31:0] previous_wdata;
    logic [31:0] previous_araddr;
    int unsigned aw_stalls;
    int unsigned w_stalls;
    int unsigned ar_stalls;

    function new(virtual axi_lite_if vif, mailbox #(axi_transaction) observed);
      this.vif = vif;
      this.observed = observed;
      aw_seen = 0;
      w_seen = 0;
      previous_aw_stall = 0;
      previous_w_stall = 0;
      previous_ar_stall = 0;
      aw_stalls = 0;
      w_stalls = 0;
      ar_stalls = 0;
    endfunction

    task run(int unsigned expected_count);
      axi_transaction sample;
      int unsigned completed;
      completed = 0;
      while (completed < expected_count) begin
        @(posedge vif.clk);
        if (vif.rst_n) begin
          if (previous_aw_stall && (!vif.awvalid || vif.awaddr !== previous_awaddr))
            $fatal(1, "AXI AW payload changed under backpressure");
          if (previous_w_stall && (!vif.wvalid || vif.wdata !== previous_wdata))
            $fatal(1, "AXI W payload changed under backpressure");
          if (previous_ar_stall && (!vif.arvalid || vif.araddr !== previous_araddr))
            $fatal(1, "AXI AR payload changed under backpressure");

          if (vif.awvalid && vif.awready) begin
            aw_seen = 1;
            saved_awaddr = vif.awaddr;
          end
          if (vif.wvalid && vif.wready) begin
            w_seen = 1;
            saved_wdata = vif.wdata;
          end
          if (vif.bvalid && vif.bready) begin
            if (!(aw_seen && w_seen))
              $fatal(1, "AXI B response occurred before AW and W handshakes");
            sample = new();
            sample.is_write = 1;
            sample.address = saved_awaddr;
            sample.data = saved_wdata;
            sample.response = vif.bresp;
            observed.put(sample);
            completed++;
            aw_seen = 0;
            w_seen = 0;
          end
          if (vif.arvalid && vif.arready)
            saved_araddr = vif.araddr;
          if (vif.rvalid && vif.rready) begin
            sample = new();
            sample.is_write = 0;
            sample.address = saved_araddr;
            sample.data = vif.rdata;
            sample.response = vif.rresp;
            observed.put(sample);
            completed++;
          end

          if (vif.awvalid && !vif.awready) aw_stalls++;
          if (vif.wvalid && !vif.wready) w_stalls++;
          if (vif.arvalid && !vif.arready) ar_stalls++;
          previous_aw_stall = vif.awvalid && !vif.awready;
          previous_w_stall = vif.wvalid && !vif.wready;
          previous_ar_stall = vif.arvalid && !vif.arready;
          previous_awaddr = vif.awaddr;
          previous_wdata = vif.wdata;
          previous_araddr = vif.araddr;
        end else begin
          previous_aw_stall = 0;
          previous_w_stall = 0;
          previous_ar_stall = 0;
        end
      end
    endtask
  endclass

  class axi_scoreboard;
    mailbox #(axi_transaction) expected;
    mailbox #(axi_transaction) observed;
    int unsigned checked;

    function new(mailbox #(axi_transaction) expected,
                 mailbox #(axi_transaction) observed);
      this.expected = expected;
      this.observed = observed;
      checked = 0;
    endfunction

    task run(int unsigned count);
      axi_transaction exp;
      axi_transaction got;
      repeat (count) begin
        expected.get(exp);
        observed.get(got);
        if (exp.transaction_id != checked)
          $fatal(1, "AXI expected stream sequence error at transaction %0d", checked);
        if (exp.is_write !== got.is_write ||
            exp.address !== got.address ||
            exp.data !== got.data ||
            got.response !== 2'b00)
          $fatal(1, "AXI scoreboard mismatch at transaction %0d", exp.transaction_id);
        checked++;
      end
      $display("AXI scoreboard PASS: %0d completed transactions", checked);
    endtask
  endclass

  class axi_environment;
    virtual axi_lite_if vif;
    mailbox #(axi_transaction) requests;
    mailbox #(axi_transaction) expected;
    mailbox #(axi_transaction) observed;
    axi_generator generator;
    axi_driver driver;
    axi_monitor monitor;
    axi_scoreboard scoreboard;
    int unsigned transaction_count;

    function new(virtual axi_lite_if vif, int unsigned count);
      this.vif = vif;
      transaction_count = count;
      requests = new();
      expected = new();
      observed = new();
      generator = new(requests, expected);
      driver = new(vif, requests);
      monitor = new(vif, observed);
      scoreboard = new(expected, observed);
    endfunction

    task run();
      fork
        generator.run(transaction_count);
        driver.run(transaction_count);
        monitor.run(transaction_count);
        scoreboard.run(transaction_count);
      join
      if (monitor.aw_stalls == 0 || monitor.w_stalls == 0 || monitor.ar_stalls == 0)
        $fatal(1, "AXI backpressure coverage missing: AW=%0d W=%0d AR=%0d",
               monitor.aw_stalls, monitor.w_stalls, monitor.ar_stalls);
      $display("AXI coverage PASS: AW stalls=%0d W stalls=%0d AR stalls=%0d",
               monitor.aw_stalls, monitor.w_stalls, monitor.ar_stalls);
    endtask
  endclass
endpackage
