`timescale 1ns/1ps

package jtag_env_pkg;
  localparam logic [3:0] TAP_TEST_LOGIC_RESET = 4'd0;
  localparam logic [3:0] TAP_RUN_TEST_IDLE = 4'd1;
  localparam logic [3:0] TAP_SELECT_DR_SCAN = 4'd2;
  localparam logic [3:0] TAP_CAPTURE_DR = 4'd3;
  localparam logic [3:0] TAP_SHIFT_DR = 4'd4;
  localparam logic [3:0] TAP_EXIT1_DR = 4'd5;
  localparam logic [3:0] TAP_PAUSE_DR = 4'd6;
  localparam logic [3:0] TAP_EXIT2_DR = 4'd7;
  localparam logic [3:0] TAP_UPDATE_DR = 4'd8;
  localparam logic [3:0] TAP_SELECT_IR_SCAN = 4'd9;
  localparam logic [3:0] TAP_CAPTURE_IR = 4'd10;
  localparam logic [3:0] TAP_SHIFT_IR = 4'd11;
  localparam logic [3:0] TAP_EXIT1_IR = 4'd12;
  localparam logic [3:0] TAP_PAUSE_IR = 4'd13;
  localparam logic [3:0] TAP_EXIT2_IR = 4'd14;
  localparam logic [3:0] TAP_UPDATE_IR = 4'd15;

  class jtag_transaction;
    int unsigned cycle_id;
    logic tms;
    logic tdi;
    logic shift_enable;
    logic [31:0] tdi_word;
    logic [31:0] tdo_word;
    logic [3:0] tap_state;
    logic tdo;
    logic [31:0] shift_tdi;
    logic [31:0] shift_tdo;
    logic tck;

    function new();
      cycle_id = 0;
      tms = 0;
      tdi = 0;
      shift_enable = 0;
      tdi_word = 0;
      tdo_word = 0;
      tap_state = 0;
      tdo = 0;
      shift_tdi = 0;
      shift_tdo = 0;
      tck = 0;
    endfunction
  endclass

  class jtag_generator;
    mailbox #(jtag_transaction) to_driver;
    mailbox #(jtag_transaction) expected;
    int unsigned cycle_count;
    logic [31:0] lfsr;

    function new(mailbox #(jtag_transaction) driver_mbx,
                 mailbox #(jtag_transaction) expected_mbx);
      to_driver = driver_mbx;
      expected = expected_mbx;
      cycle_count = 0;
      lfsr = 32'h1ACE_B00C;
    endfunction

    task automatic emit(logic tms, logic tdi, logic shift_enable,
                        logic [31:0] tdi_word, logic [31:0] tdo_word);
      jtag_transaction req;
      jtag_transaction exp;
      req = new();
      exp = new();
      req.cycle_id = cycle_count;
      req.tms = tms;
      req.tdi = tdi;
      req.shift_enable = shift_enable;
      req.tdi_word = tdi_word;
      req.tdo_word = tdo_word;
      exp.cycle_id = cycle_count;
      exp.tms = tms;
      exp.tdi = tdi;
      exp.shift_enable = shift_enable;
      exp.tdi_word = tdi_word;
      exp.tdo_word = tdo_word;
      expected.put(exp);
      to_driver.put(req);
      cycle_count++;
    endtask

    task run();
      emit(1, 0, 0, 0, 0);
      emit(0, 1, 0, 0, 0);
      emit(1, 0, 0, 0, 0);
      emit(0, 1, 0, 0, 0);
      emit(0, 0, 1, 32'h0123_4567, 32'h89AB_CDEF);
      emit(1, 1, 0, '1, '1);
      emit(0, 0, 0, 0, 0);
      emit(1, 1, 0, 0, 0);
      emit(0, 0, 0, 0, 0);
      emit(1, 0, 0, 0, 0);
      emit(1, 1, 0, 0, 0);
      emit(0, 0, 0, 0, 0);
      emit(1, 0, 0, 0, 0);
      emit(1, 1, 0, 0, 0);
      emit(0, 0, 0, 0, 0);
      emit(0, 1, 0, 0, 0);
      emit(1, 0, 0, 0, 0);
      emit(0, 1, 0, 0, 0);
      emit(1, 0, 0, 0, 0);
      emit(0, 0, 0, 0, 0);
      emit(1, 1, 0, 0, 0);
      emit(1, 0, 0, 0, 0);
      emit(1, 1, 0, 0, 0);
      emit(1, 0, 0, 0, 0);
      emit(1, 1, 0, 0, 0);

      repeat (1000) begin
        lfsr = {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
        emit(lfsr[4], lfsr[9], lfsr[13],
             lfsr ^ (32'h9E37_79B9 * cycle_count),
             {lfsr[15:0], lfsr[31:16]});
      end
    endtask
  endclass

  class jtag_driver;
    virtual jtag_if vif;
    mailbox #(jtag_transaction) requests;

    function new(virtual jtag_if vif, mailbox #(jtag_transaction) requests);
      this.vif = vif;
      this.requests = requests;
    endfunction

    task run(int unsigned count);
      jtag_transaction req;
      repeat (count) begin
        requests.get(req);
        @(negedge vif.clk);
        vif.tms = req.tms;
        vif.tdi = req.tdi;
        vif.shift_enable = req.shift_enable;
        vif.tdi_word = req.tdi_word;
        vif.tdo_word = req.tdo_word;
      end
    endtask
  endclass

  class jtag_monitor;
    virtual jtag_if vif;
    mailbox #(jtag_transaction) observed;

    function new(virtual jtag_if vif, mailbox #(jtag_transaction) observed);
      this.vif = vif;
      this.observed = observed;
    endfunction

    task run(int unsigned count);
      jtag_transaction sample;
      @(negedge vif.clk);
      repeat (count) begin
        @(posedge vif.clk);
        #1;
        sample = new();
        sample.tap_state = vif.tap_state;
        sample.tdo = vif.tdo;
        sample.shift_tdi = vif.shift_tdi;
        sample.shift_tdo = vif.shift_tdo;
        sample.tck = vif.tck;
        observed.put(sample);
      end
    endtask
  endclass

  class jtag_scoreboard;
    mailbox #(jtag_transaction) expected;
    mailbox #(jtag_transaction) observed;
    int unsigned state_hits[16];
    int unsigned tck_edges;
    logic [3:0] model_state;
    logic [31:0] model_shift_tdi;
    logic [31:0] model_shift_tdo;
    logic previous_tck;

    function new(mailbox #(jtag_transaction) expected,
                 mailbox #(jtag_transaction) observed);
      this.expected = expected;
      this.observed = observed;
      model_state = TAP_TEST_LOGIC_RESET;
      model_shift_tdi = 0;
      model_shift_tdo = 0;
      previous_tck = 0;
      tck_edges = 0;
      foreach (state_hits[i]) state_hits[i] = 0;
    endfunction

    function automatic logic [3:0] next_state(logic [3:0] s, logic m);
      case (s)
        TAP_TEST_LOGIC_RESET: next_state = m ? TAP_TEST_LOGIC_RESET : TAP_RUN_TEST_IDLE;
        TAP_RUN_TEST_IDLE: next_state = m ? TAP_SELECT_DR_SCAN : TAP_RUN_TEST_IDLE;
        TAP_SELECT_DR_SCAN: next_state = m ? TAP_SELECT_IR_SCAN : TAP_CAPTURE_DR;
        TAP_CAPTURE_DR: next_state = m ? TAP_EXIT1_DR : TAP_SHIFT_DR;
        TAP_SHIFT_DR: next_state = m ? TAP_EXIT1_DR : TAP_SHIFT_DR;
        TAP_EXIT1_DR: next_state = m ? TAP_UPDATE_DR : TAP_PAUSE_DR;
        TAP_PAUSE_DR: next_state = m ? TAP_EXIT2_DR : TAP_PAUSE_DR;
        TAP_EXIT2_DR: next_state = m ? TAP_UPDATE_DR : TAP_SHIFT_DR;
        TAP_UPDATE_DR: next_state = m ? TAP_SELECT_DR_SCAN : TAP_RUN_TEST_IDLE;
        TAP_SELECT_IR_SCAN: next_state = m ? TAP_TEST_LOGIC_RESET : TAP_CAPTURE_IR;
        TAP_CAPTURE_IR: next_state = m ? TAP_EXIT1_IR : TAP_SHIFT_IR;
        TAP_SHIFT_IR: next_state = m ? TAP_EXIT1_IR : TAP_SHIFT_IR;
        TAP_EXIT1_IR: next_state = m ? TAP_UPDATE_IR : TAP_PAUSE_IR;
        TAP_PAUSE_IR: next_state = m ? TAP_EXIT2_IR : TAP_PAUSE_IR;
        TAP_EXIT2_IR: next_state = m ? TAP_UPDATE_IR : TAP_SHIFT_IR;
        TAP_UPDATE_IR: next_state = m ? TAP_SELECT_DR_SCAN : TAP_RUN_TEST_IDLE;
        default: next_state = TAP_TEST_LOGIC_RESET;
      endcase
    endfunction

    task run(int unsigned count);
      jtag_transaction exp;
      jtag_transaction got;
      repeat (count) begin
        expected.get(exp);
        observed.get(got);
        model_state = next_state(model_state, exp.tms);
        if (exp.shift_enable) begin
          model_shift_tdi = exp.tdi_word;
          model_shift_tdo = exp.tdo_word;
        end
        if (got.tap_state !== model_state)
          $fatal(1, "JTAG cycle %0d: TAP expected %0d got %0d",
                 exp.cycle_id, model_state, got.tap_state);
        if (got.tdo !== exp.tdi)
          $fatal(1, "JTAG cycle %0d: TDO expected %b got %b",
                 exp.cycle_id, exp.tdi, got.tdo);
        if (got.shift_tdi !== model_shift_tdi || got.shift_tdo !== model_shift_tdo)
          $fatal(1, "JTAG cycle %0d: shift engine output mismatch", exp.cycle_id);
        state_hits[model_state]++;
        if (got.tck !== previous_tck) tck_edges++;
        previous_tck = got.tck;
      end
      foreach (state_hits[i])
        if (state_hits[i] == 0) $fatal(1, "JTAG TAP state %0d not visited", i);
      if (tck_edges < 4) $fatal(1, "JTAG TCK toggled only %0d times", tck_edges);
      $display("JTAG scoreboard PASS: %0d cycles, TCK edges=%0d", count, tck_edges);
    endtask
  endclass

  class jtag_environment;
    mailbox #(jtag_transaction) requests;
    mailbox #(jtag_transaction) expected;
    mailbox #(jtag_transaction) observed;
    jtag_generator generator;
    jtag_driver driver;
    jtag_monitor monitor;
    jtag_scoreboard scoreboard;
    virtual jtag_if vif;
    int unsigned count;

    function new(virtual jtag_if vif);
      this.vif = vif;
      requests = new();
      expected = new();
      observed = new();
      count = 1025;
      generator = new(requests, expected);
      driver = new(vif, requests);
      monitor = new(vif, observed);
      scoreboard = new(expected, observed);
    endfunction

    task run();
      fork
        generator.run();
        driver.run(count);
        monitor.run(count);
        scoreboard.run(count);
      join
    endtask
  endclass
endpackage
