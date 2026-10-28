# FPGA Programmer RTL: Technical Reference

## Design scope

This repository is a modular SystemVerilog implementation scaffold for an FPGA programmer. The intended data path is external flash → memory controller → DMA stream → JTAG target. UART is the host command and response path. The controller FSM sequences operations, while individual blocks own packet handling, memory transactions, stream movement, and TAP signaling.

The RTL is currently an architectural prototype. Several blocks are simplified or are not connected end-to-end; this document distinguishes implemented behavior from intended behavior rather than treating the scaffold as a finished programmer.

## Whole-system operation

The intended path is:

```text
Host
  -> UART receiver and packet parser
  -> programmer_controller (command/configuration FSM)
  -> memory_manager -> SPI, QSPI, or OSPI flash
  -> DMA / AXI-Stream data path
  -> JTAG controller -> target
  -> UART response
```

`fpga_programmer_top.sv` instantiates the UART protocol wrapper, programmer controller, memory manager, and JTAG controller. The UART protocol produces decoded command, length, payload, CRC, and packet status signals. The programmer controller consumes those signals and creates configuration, start, abort, and response signals. The memory manager uses the configured memory type to select a flash interface. The JTAG controller drives the target pins, while the UART response generator serializes controller responses for the host.

That describes the intended architecture, not a fully functioning end-to-end programmer. Some blocks currently use placeholder behavior, and the top-level does not connect the flash data through a functional DMA stream into JTAG. The current implemented connections and gaps are called out below.

### What happens to a host request

The host sends bytes to `uart_rx`. `uart_protocol` combines the UART receiver, packet parser, response generator, and UART transmitter. The parser expects this frame:

```text
SOF | command | payload_length[15:8] | payload_length[7:0] |
payload bytes | CRC[15:8] | CRC[7:0] | EOF
```

The defined frame markers are `8'hAA` for SOF and `8'h55` for EOF. The parser begins its CRC accumulator at `16'hFFFF` and uses the package CRC update function. The precise host-side CRC convention should still be frozen and tested against a reference implementation before relying on protocol interoperability.

On a valid frame, the parser raises `packet_valid` and provides the command, payload length, payload array, and CRC to `programmer_controller`. On a malformed frame it raises `packet_error` with an error code. The controller produces a response ID, response payload, response length, and a one-cycle `response_trigger`; the UART response generator and transmitter send that response to the host.

The configure command currently interprets payload bytes as follows:

| Payload byte(s) | Field |
|---|---|
| 0 | Memory type in bits `[2:0]` |
| 1-4 | Memory address, most-significant byte first |
| 5-8 | Bitstream length, most-significant byte first |
| 9-12 | Expected JTAG IDCODE, most-significant byte first |
| 13-16 | JTAG frequency, most-significant byte first |
| 17 | JTAG mode |
| 18 | Trigger type in bits `[2:0]` |
| 19-20 | Bitstream ID, most-significant byte first |
| 21 | Flags |

These are the offsets currently read by the RTL, not a fully validated protocol contract. The FSM does not yet verify that a configure payload contains all 22 bytes before accessing these entries.

### Programmer-controller sequence and peripheral handshakes

The controller's outputs are registered pulses or stored configuration values. The intended interaction among its phases is:

| Controller phase | Current RTL action | Intended system role |
|---|---|---|
| `CTRL_IDLE` | Accepts configure, start, or abort; rejects other commands | Receive a new host operation |
| `CTRL_MEMORY_CONFIG` | Sends a status response and advances | Confirm stored flash configuration |
| `CTRL_DMA_CONFIG` | Pulses `start_dma` for one clock | Start the source-data transfer |
| `CTRL_JTAG_CONFIG` | Pulses `start_jtag` for one clock | Prepare/start the JTAG operation |
| `CTRL_START_TRANSFER` | Waits for `memory_done`; then reports program started | Wait for flash setup/read completion |
| `CTRL_WAIT_TRANSFER` | Waits for `dma_done`, or handles peripheral errors | Wait for data movement/programming |
| `CTRL_VERIFY` | Waits for `idcode_ready`, then compares IDCODE | Verify the target after programming |
| `CTRL_REPORT_SUCCESS` | Clears controller busy and returns idle | Finish a successful operation |
| `CTRL_ERROR` / `CTRL_ABORT` | Sends an error/NACK response; abort pulses DMA/JTAG | Report failure or stop peripherals |

In the current top-level, `start_dma` is wired directly to `memory_manager.read_req`; it starts a flash read rather than a connected DMA engine. `memory_done` is the manager's completion output. The top-level does not instantiate `dma_controller`, so `dma_done` and `dma_error` are tied low. It also leaves memory `read_data` unconnected and ties JTAG `tx_data` to zero. Consequently, the current design cannot carry the flash contents through to the JTAG target, and the normal FSM cannot leave `CTRL_WAIT_TRANSFER` through a DMA completion.

There is also a sequencing distinction to keep in mind: a configure packet currently advances automatically through the memory/DMA/JTAG configuration phases and pulses the start outputs. A `CMD_START` received in idle only enters `CTRL_START_TRANSFER`; it does not itself generate those pulses. `CMD_STATUS`, `CMD_READ_ID`, and `CMD_RESET` are declared in the shared command enum but are not implemented as successful controller commands. These behaviors need a protocol decision and FSM changes before the host interface should be treated as stable.

## Repository layout

```text
rtl/
  axi/         AXI-Lite/AXI-Stream interfaces, master, interconnect
  common/      Shared package, reset synchronizer, FIFOs
  controller/  Programmer FSM, register bank, IRQ, timeout, trigger blocks
  dma/         DMA registers, stream source, controller
  jtag/        TCK generator, TAP, shift engine, JTAG wrapper/registers/FIFOs
  memory/      Memory manager and SPI/QSPI/OSPI read controllers
  storage/     Internal configuration RAM
  top/         FPGA programmer integration module
tb/
  tb_*.sv      Initial subsystem and top-level benches
  models/      NOR flash and JTAG-target behavioral models
jtag_tb/       Pure SystemVerilog checks for TAP, shift engine, TCK
axi_tb/        Pure SystemVerilog checks for AXI-Lite master
```

## Shared types: `rtl/common/programmer_pkg.sv`

The package is compiled before modules that import its definitions. It sets default clock, bus, stream, UART, FIFO, JTAG, RAM, and memory-address parameters. It defines:

- `memory_type_t`: SPI, QSPI, and OSPI encodings.
- `trigger_type_t`: manual, GPIO, timer, external, target-feedback, and error-recovery trigger choices.
- UART command and response enums, plus error, IRQ, DMA, controller, and TAP-state enums.
- Packed configuration and descriptor records (`programmer_config_t`, `bitstream_descriptor_t`) and fixed-width AXI/stream typedefs.
- `crc16_update`, an incremental CRC-16/CCITT-style update using polynomial `16'h1021`.

Packet framing constants are `UART_SOF = 8'hAA` and `UART_EOF = 8'h55`. Protocol framing, field ordering, and CRC initialization/finalization should be treated as a project protocol definition that still needs a frozen host-side specification.

## Common blocks

### Reset synchronizer

`rtl/common/reset_sync.sv` synchronizes reset release into a clock domain. It is intended for reset-domain hygiene; asynchronous assertion and synchronous deassertion details must be confirmed against the target FPGA reset requirements.

### FIFOs

`rtl/common/sync_fifo.sv` implements a single-clock memory FIFO with write/read pointers, count, full/empty and almost-full/almost-empty indicators. It drives registered read data on a successful read. The implementation contains simulation-only checks for writes while full and reads while empty. `async_fifo.sv` is an architectural placeholder and must not be assumed to provide a production CDC FIFO until implemented and verified.

## UART control plane

The UART modules are composed by `rtl/uart/uart_protocol.sv`:

1. `uart_rx.sv` samples the serial input and produces received bytes plus a valid indication.
2. `uart_packet_parser.sv` consumes valid bytes, tracks packet framing/length/payload/CRC and produces packet status and command fields.
3. `uart_response_generator.sv` formats response data into serializable bytes.
4. `uart_tx.sv` sends those bytes on the serial output.
5. `crc16.sv` provides a standalone CRC helper; the package also defines a CRC update function.

The protocol wrapper transports parsed requests and caller-supplied responses. `programmer_controller.sv` is the separate command sequencing block, and `fpga_programmer_top.sv` connects its packet inputs and response outputs to the UART wrapper. UART packets can therefore reach the controller, but command coverage, packet-format validation, and the complete programming flow still need work.

## Control and register blocks

### Programmer FSM

`rtl/controller/programmer_controller.sv` is the system-level command and sequencing FSM. It accepts a decoded UART packet (`packet_valid`, `packet_error`, `command`, `length`, `payload`) and completion/error indications from memory, DMA, and JTAG. It stores the configuration fields and emits response pulses plus start/abort control pulses.

The implemented control flow is currently:

1. In `CTRL_IDLE`, a valid `CMD_CONFIGURE` copies fields from fixed payload offsets into the memory type/address/bitstream length, expected IDCODE, JTAG frequency/mode, trigger type, bitstream ID, and flags outputs. It sends an ACK and enters `CTRL_MEMORY_CONFIG`.
2. `CTRL_MEMORY_CONFIG` reports a status response and advances to `CTRL_DMA_CONFIG`. `CTRL_DMA_CONFIG` pulses `start_dma`, then `CTRL_JTAG_CONFIG` pulses `start_jtag`.
3. `CTRL_START_TRANSFER` waits for `memory_done` before reporting `RESP_PROGRAM_STARTED` and entering `CTRL_WAIT_TRANSFER`.
4. `CTRL_WAIT_TRANSFER` waits for `dma_done`, then enters `CTRL_VERIFY`. DMA, memory, or JTAG errors send a program-error response.
5. `CTRL_VERIFY` compares `idcode_value` to `expected_idcode`. A match reports completion; a mismatch reports an IDCODE error. `CMD_ABORT` pulses the DMA/JTAG abort outputs.

This sequence is only a scaffold and must not be interpreted as a complete host-visible programming protocol. In the current RTL, configuring automatically pulses the DMA and JTAG starts; `CMD_START` also moves to `CTRL_START_TRANSFER` but does not itself generate those start pulses. `CMD_STATUS`, `CMD_READ_ID`, and `CMD_RESET` are defined but are not handled as successful commands by the FSM. The top-level ties `dma_done` and `dma_error` low, so the FSM cannot advance past `CTRL_WAIT_TRANSFER` in an actual top-level run. Configuration payload length/content is not fully validated before fields are read. Correct command semantics, field validation, repeated-command handling, timeout/error recovery, abort behavior, and corresponding tests remain to be implemented.

### Programmer register bank

`rtl/controller/programmer_regs.sv` provides a basic register map for control, status, error, configuration words, and IDCODE. It exposes configuration and status outputs and implements a simple always-ready, one-cycle style interface. Byte strobes and fully independent AXI AW/W channel capture are not implemented robustly yet.

### Interrupts, triggers, timeout

- `interrupt_controller.sv`: sticky interrupt status with enable/clear behavior.
- `trigger_manager.sv`: selects/handles trigger-source logic.
- `timeout_manager.sv`: timeout/watchdog counting.

These are standalone helper blocks; the top-level integration must connect their events and controls before the functionality is available to a host.

## AXI blocks

### AXI-Lite master

`rtl/axi/axi_lite_master.sv` converts simple `write_req`/`read_req` requests into AXI-Lite channels. It has one transaction state at a time, supports a write address/data request followed by a write response, or a read address followed by a read response. It does not support bursts, multiple outstanding requests, or arbitration. Its `wstrb` is driven as all ones.

The separate AW and W channels can handshake independently. The verification environment in `axi_tb/` deliberately varies readiness independently and checks that requests remain stable under backpressure and that responses are associated with the expected operation.

### AXI-Lite interconnect

`rtl/axi/axi_lite_interconnect.sv` is intended as a single-master static slave selector. It routes valid/ready/response channels based on `sel`. The current interface omits forwarded AW address, W data/strobes, and AR address outputs to the selected slave, so it is not yet a complete usable AXI-Lite interconnect. It also registers several returned signals. Treat it as a placeholder pending interface correction and protocol verification.

### Interfaces

`axi_lite_slave_if.sv` describes AXI-Lite signal directions through master/slave modports. `axi_stream_if.sv` describes a basic ready/valid stream with `tdata`, `tkeep`, and `tlast`.

## Memory and data path

### Memory interface and manager

`rtl/memory/memory_interface.sv` describes the common read handshake. `memory_manager.sv` receives that request and selects one of three physical flash controllers using `memory_type`: `MEM_SPI`, `MEM_QSPI`, or `MEM_OSPI`.

The normal transaction sequence is:

1. The caller supplies `memory_type`, `addr`, and `length`, then raises `read_req` for a rising edge. Keep these fields stable while presenting the request.
2. The manager detects the rising edge of `read_req`. If no transfer is active, it sends a one-cycle request only to the selected controller and records the selected type.
3. The selected controller validates `length` and its clock divider. A valid request lowers that flash's active-low chip select and begins the read. The manager asserts `busy` while waiting.
4. The controller raises `done` for one cycle after sampling the requested data bits, or raises `error` for one cycle if the request is invalid. The manager forwards the selected controller's result and deasserts `busy`.

The manager exposes separate SCLK, CS, and data pins for each interface. SPI uses `sclk`, `cs_n`, `mosi`, and `miso`; QSPI and OSPI use their respective clock/chip-select outputs and bidirectional IO buses. Unselected controllers do not receive the request. An unsupported `memory_type` produces an error without starting a flash transaction. Requests made while the manager is busy are not queued. A new request must have a low period before its next rising edge.

### Shared serial-flash read engine

`rtl/memory/serial_flash_read_engine.sv` implements the transaction state machine used by all three wrappers. It has five phases:

1. **Idle:** SCLK is low and CS is high. A new rising edge on `read_req` starts a transaction if the request passes validation.
2. **Command:** The engine transmits the configured 8-bit read opcode. In SPI and QSPI it sends one bit per serial clock on one lane. In OSPI the opcode is sent in one 8-bit, octal-lane transfer.
3. **Address:** The engine transmits `addr`, most-significant bits first. It sends one bit per clock for SPI and one nibble per clock for QSPI. OSPI sends one byte per clock.
4. **Dummy:** The engine produces the configured number of dummy serial-clock cycles before accepting data. This count is in clock cycles, not bits.
5. **Data:** The engine samples the IO input lanes on its active sampling edge, shifts the sampled bits into `read_data`, and counts down `length`. On the final sample it deasserts CS, returns to idle, and pulses `done`.

The state machine advances from the low-to-high SCLK transition. SCLK is CPOL=0 (idle low); this implementation is a simple SDR read engine, not a complete implementation of every vendor's SPI/QSPI/OSPI protocol. Use a flash device and opcode/timing profile compatible with this sequencing.

#### Widths, configuration, and validation

- `addr` is `ADDR_WIDTH` bits (24 by default).
- `length` is the number of **data bits** to receive, not a byte count. It must be nonzero and divisible by the number of data lanes: 1 for SPI, 4 for QSPI, or 8 for OSPI.
- `read_data` is `DATA_WIDTH` bits (32 by default). Incoming bits are shifted into this register, so when more than `DATA_WIDTH` bits are read it contains the most recently received `DATA_WIDTH` bits.
- `cfg_read_opcode`, `cfg_dummy_cycles`, and `cfg_clk_divider` are latched when the request starts. The divider is the number of system-clock cycles per SCLK half-period; for example, a value of 5 gives an SCLK period of 10 system-clock cycles. The manager derives it from the configured frequencies as `CLK_FREQ_HZ / (2 * *_CLK_FREQ_HZ)`, with a minimum divider of 1.
- Each wrapper also has parameter defaults for its opcode, dummy cycles, and SCLK frequency. The manager passes those values through the runtime configuration ports. Defaults are SPI opcode `8'h03` with 0 dummy cycles, QSPI opcode `8'hEB` with 2 dummy cycles, and OSPI opcode `8'hEC` with 2 dummy cycles.
- A zero length, lane-unaligned length, or zero divider is rejected with a one-cycle `error` pulse. A rejected request does not start clocking the flash.
- `busy` is asserted during a valid transfer. `done` and `error` are one-cycle status pulses. `cs_n` stays low during the transaction and returns high at completion.

The thin `spi_controller`, `qspi_controller`, and `ospi_controller` wrappers adapt the shared engine to their physical pins. SPI drives MOSI only while the engine is transmitting. QSPI/OSPI drive their inout buses during command/address phases and release them for dummy/data phases so the flash can drive read data.

This controller returns one `DATA_WIDTH`-wide result register; it does not stream arbitrarily long reads to DMA. The current top-level connects the manager's completion handshake but leaves its read data unconnected, and DMA completion is tied inactive. Therefore the memory block can be exercised independently, but the full flash-to-DMA-to-JTAG programming path is not yet integrated.

### SPI controller

`spi_controller.sv` is the one-lane wrapper for a conventional SPI-NOR read. It sends opcode and address on MOSI, then samples MISO. The engine is configured for mode 0 timing (CPOL=0, with data sampling/phase behavior defined by its state transitions). The SPI clock rate, opcode, and dummy cycles are set by parameters and passed by `memory_manager`.

### DMA

`dma_regs.sv` exposes source address, transfer length, start, and abort controls. `dma_stream_source.sv` and `dma_controller.sv` provide a simple memory-to-stream architecture with valid/ready/last-style transfer intent and done/error state. This is not a scatter/gather engine and currently lacks a fully verified connection from SPI reads through the stream into the JTAG shift path.

## JTAG data path

### TAP

`rtl/jtag/jtag_tap.sv` implements the 16-state IEEE 1149.1 TAP transition table. On each system-clock rising edge, `current_state` advances according to TMS; `tap_state` reflects the current registered state. The current TDO behavior is a registered copy of TDI and is only a functional placeholder: real JTAG TDO is selected from the active instruction/data register and is timed relative to TCK.

### TCK generation

`jtag_clock.sv` divides the system clock based on `CLK_FREQ_HZ / jtag_frequency` and toggles TCK. The current implementation uses a programmable count and has not yet been verified for all requested frequencies, zero/overspeed values, duty-cycle requirements, or divider off-by-one behavior.

### Shift engine and controller

`jtag_shift_engine.sv` captures whole `tdi_word` and `tdo_word` values when `shift_enable` is asserted; it is not yet a serial, bit-counted shift register. `jtag_controller.sv` starts a simplified count-based operation when `tx_valid` is observed, samples TDO into `rx_data`, and reports a simplified IDCODE/status result. The IDCODE result currently mirrors `expected_idcode` rather than obtaining and comparing a value shifted from a real target. Thus this is a control-flow scaffold, not a bitstream-capable JTAG programming engine.

`jtag_regs.sv`, `jtag_tx_fifo.sv`, and `jtag_rx_fifo.sv` provide initial configuration/register and FIFO plumbing. Their AXI register semantics and FIFO integration need further verification.

## Top-level integration

`rtl/top/fpga_programmer_top.sv` declares host UART, GPIO, JTAG, and SPI/QSPI/OSPI flash pins. UART packet fields and the controller's response interface are connected. The controller's memory type, address, and length feed `memory_manager`; its `start_dma` pulse is currently connected directly to the manager's `read_req`. The manager's `read_data` output is left unconnected. The DMA RTL is not instantiated in the top-level, and `dma_done`/`dma_error` are tied low. JTAG start/configuration signals reach `jtag_controller`, but no flash data is connected to its transmit input (`tx_data` is tied to zero). Consequently, the current top-level can exercise control and peripheral activity but cannot move a flash bitstream through DMA into a JTAG target or finish the complete programming FSM.

### Memory-controller simulation

The memory-manager dispatch bench is `tb/tb_serial_flash_controllers.sv`. It models QSPI and OSPI targets, checks reads through the manager for all three types, confirms only the requested flash chip select activates, and checks unsupported type/unaligned-length errors. Run it from `tb/` using `vsim -c -do run_serial_flash.do`.

## Simulation and verification

The original `tb/` benches are smoke-test scaffolding for UART, memory, JTAG, controller, and top-level wiring. The models in `tb/models/` provide initial NOR flash and JTAG target behavioral models; model fidelity must be matched to the implemented protocol before treating tests as sign-off.

The additional self-checking SystemVerilog test environments use standard SystemVerilog OOP concepts (classes, transaction objects, virtual interfaces, mailboxes, generator, driver, monitor, scoreboard, environment, and test). They are UVM-style but use no UVM package, DPI, external library, or Quartus database.

- `jtag_tb/`: a transaction generator, virtual-interface driver, output monitor, TAP/shift/TCK scoreboard, environment, and top-level test. Stimulus includes directed TAP state walks and 1,000 deterministic pseudo-random cycles.
- `axi_tb/`: an operation generator, virtual-interface master driver/subordinate model, protocol monitor, transaction scoreboard, environment, and top-level test. It runs 20 reads and 20 writes with independent channel backpressure and delayed responses.

Both directories contain a `run.do` script for ModelSim/Questa. The testbenches are plain SystemVerilog modules: they do not require UVM, DPI, foreign libraries, or Quartus-generated database files. Both compile and pass using the installed ModelSim Intel FPGA Starter Edition.

## Verification and implementation status

The codebase has had iterative compile cleanup, including enum-width correction, simplifying AXI signal ports for simulator compatibility, and repairing UART response array assignment. The full project still needs a clean compile/elaboration pass over all modules and benches using the selected simulator.

Before hardware use or claiming functional programming support, the next engineering gates are:

1. Extend the focused SystemVerilog tests as additional JTAG and AXI behavior is implemented.
2. Correct any regressions exposed by the JTAG and AXI scoreboards.
3. Implement a serial bit-counted JTAG shift path and proper target-driven IDCODE capture.
4. Implement/specify valid SPI flash command framing and check reads against the target flash model.
5. Wire controller, memory, DMA, JTAG, registers, and interrupts through the top-level.
6. Add end-to-end programming tests, malformed packet/error tests, reset/abort tests, and parameter boundary tests.
7. Run synthesis and timing analysis on the chosen FPGA toolchain.

## Running the SystemVerilog benches

From either test directory in ModelSim/Questa, run:

```powershell
vsim -c -do run.do
```

Each testbench stops with `$fatal` on a detected mismatch and prints `PASS` when its checks complete.
