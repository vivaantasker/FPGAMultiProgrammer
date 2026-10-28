# JTAG Class-Based SystemVerilog Testbench

This is a UVM-style verification environment implemented with standard SystemVerilog classes, mailboxes, and a virtual interface. It has no UVM, DPI, or Quartus dependency.

Components in `jtag_env_pkg.sv`:

- `jtag_transaction`: stimulus and observed transaction data.
- `jtag_generator`: sends a directed TAP walk followed by deterministic pseudo-random cycles.
- `jtag_driver`: drives JTAG inputs through a virtual interface.
- `jtag_monitor`: samples DUT outputs and publishes observations.
- `jtag_scoreboard`: predicts TAP transitions, TDO latency, shift-engine contents, and checks state/TCK coverage.
- `jtag_environment`: constructs and runs the components concurrently.

`tb_jtag.sv` instantiates the interface and RTL DUTs, applies reset, and runs the environment.

Run from this directory with ModelSim/Questa:

```text
vsim -c -do run.do
```
