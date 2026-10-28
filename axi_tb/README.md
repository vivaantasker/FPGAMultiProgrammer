# AXI-Lite Class-Based SystemVerilog Testbench

This UVM-style test environment uses standard SystemVerilog OOP classes, mailboxes, and a virtual interface only. It does not depend on UVM, DPI, Quartus, or external libraries.

`axi_env_pkg.sv` contains:

- `axi_transaction`: a read/write operation with ID, address, data, and response.
- `axi_generator`: creates an ordered stream of 20 writes and 20 reads.
- `axi_driver`: drives the request side and models a delayed AXI-Lite subordinate with independent AW/W/AR backpressure.
- `axi_monitor`: observes handshakes, checks payload stability and B-channel ordering, then publishes completed transactions.
- `axi_scoreboard`: compares generated requests against observed bus completions and checks response status.
- `axi_environment`: constructs components, connects mailboxes, runs concurrent processes, and checks backpressure coverage.

`axi_lite_if.sv` is the virtual-interface signal bundle; `tb_axi_lite_master.sv` instantiates the DUT, clock/reset, and environment.

Run from this directory:

```text
vsim -c -do run.do
```
