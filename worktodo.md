# Project Work To Do

This checklist describes the remaining work to turn the current RTL scaffold into a verified FPGA programmer. Items are grouped by dependency: settle the external behavior first, complete the datapaths next, then integrate and validate the system.

## 1. Freeze the host and flash protocols

- [ ] Specify the UART packet format completely: field byte order, payload lengths for every command, CRC coverage/initialization/finalization, and error responses. Keep the specification consistent with `rtl/uart/uart_packet_parser.sv`, `rtl/uart/uart_response_generator.sv`, and `rtl/common/programmer_pkg.sv`.
- [ ] Define the behavior and payload formats for every host command: configure, start, status, abort, read ID, reset, and read error. Decide whether configure should start a transfer or only store configuration.
- [ ] Define the supported flash parts and their actual command/address/data lane phases, opcode, dummy timing, SPI mode, address width, and whether addresses are byte- or bit-addressed. The current profiles in `rtl/memory/` are generic and may not match a particular vendor device.
- [ ] Decide whether the memory read interface transfers a single bounded word or an arbitrary bitstream. The current flash engine has a `DATA_WIDTH`-wide result register; it does not provide a streaming interface for long reads.

## 2. Complete UART and command handling

- [ ] Validate packet length before the parser writes to its payload array; handle the maximum payload without counter wraparound. Reject malformed, truncated, and unsupported packets cleanly.
- [ ] Verify CRC behavior against a host-side reference implementation, including empty payloads and boundary lengths.
- [ ] Implement all documented commands in `rtl/controller/programmer_controller.sv`. Return consistent ACK/NACK/status/error responses and set response payload length and error fields on every response path.
- [ ] Validate configuration payload size and field ranges before reading fixed payload indexes or changing configuration outputs.
- [ ] Define and implement repeated configure/start behavior, start-before-configure behavior, commands while busy, abort behavior, and reset/recovery policy.
- [ ] Add UART/parser/controller tests for every command, invalid command, CRC/framing error, short/long payload, and command sequence.

## 3. Finish the flash-to-JTAG data path

- [ ] Replace the one-result-register read path with a backpressure-aware stream or another explicitly specified transfer interface. Update `rtl/memory/serial_flash_read_engine.sv`, `rtl/memory/memory_manager.sv`, and `rtl/memory/memory_interface.sv` as needed.
- [ ] Implement a real memory-backed DMA in `rtl/dma/dma_controller.sv`. It currently emits a test pattern derived from the source address rather than reading the selected flash data.
- [ ] Choose one DMA implementation/interface and remove or clearly separate the overlapping test-pattern behavior in `rtl/dma/dma_stream_source.sv`.
- [ ] Instantiate and connect DMA in `rtl/top/fpga_programmer_top.sv`; route flash read data into DMA and DMA stream data into JTAG. Connect start, ready/backpressure, done, error, and abort signals in both directions.
- [ ] Define transfer-length units consistently across host payload, programmer controller, flash engine, DMA, and stream (`bits`, `bytes`, or `words`). Add conversion and final partial-word handling where needed.
- [ ] Add tests for multiword transfers, final partial words, backpressure, abort during a transfer, and errors at each data-path boundary.

## 4. Implement real JTAG transactions

- [ ] Replace the placeholder whole-word behavior in `rtl/jtag/jtag_shift_engine.sv` with serial, bit-counted IR/DR shifting and correct TMS sequencing.
- [ ] Make `rtl/jtag/jtag_controller.sv` obtain IDCODE from the target's TDO stream and compare the captured value. It currently reports `expected_idcode` directly rather than capturing a target response.
- [ ] Route actual DMA data to TDI instead of tying `tx_data` to zero in `rtl/top/fpga_programmer_top.sv`.
- [ ] Honor configured JTAG mode and frequency, and define behavior for unsupported frequency values and target timing.
- [ ] Add target-model tests for TAP navigation, IR/DR scans, IDCODE capture, bit order, transfer completion, and target errors.

## 5. Integrate controller handshakes and system services

- [ ] Correct the `programmer_controller` FSM so configuration, explicit start, memory read, DMA transfer, JTAG programming, IDCODE verification, completion, abort, and recovery happen in a documented order.
- [ ] Ensure a `CMD_START` causes the intended operation exactly once and that configure does not accidentally start peripherals unless that is the specified protocol.
- [ ] Add a timeout path and connect `rtl/controller/timeout_manager.sv` to memory, DMA, and JTAG waits. Report which phase timed out and recover to a defined state.
- [ ] Connect `rtl/controller/interrupt_controller.sv` and `rtl/controller/trigger_manager.sv` if interrupts/triggers are part of the product requirements; otherwise document them as unsupported and remove unused integration expectations.
- [ ] Connect status/error reporting and GPIO/LED outputs, or document these pins as reserved until implemented.
- [ ] Define reset behavior across the system and use `rtl/common/reset_sync.sv` where domain/reset requirements call for synchronized release.

## 6. Complete bus and storage blocks that are in scope

- [ ] Finish `rtl/axi/axi_lite_interconnect.sv`: forward address/data/strobes to the selected slave and verify all response/ready routing.
- [ ] Make `rtl/controller/programmer_regs.sv` correctly capture independent AXI-Lite AW and W handshakes, apply byte strobes, and define read/write response behavior.
- [ ] Decide whether AXI-Lite register access and `rtl/storage/internal_config_ram.sv` are required for the first usable release. If required, connect and verify them; otherwise mark them as optional scaffold.
- [ ] Implement and verify `rtl/common/async_fifo.sv` before using it across clock domains. Do not rely on the current placeholder for CDC.

## 7. Verification, hardware readiness, and release

- [ ] Establish a reproducible compile/elaboration file list and compile the complete top-level, not only isolated benches.
- [ ] Keep focused self-checking tests for UART, controller, memory manager, DMA, JTAG, AXI-Lite, and top-level behavior. Check outputs and protocol timing rather than only waiting for `$finish`.
- [ ] Add end-to-end tests that configure a transfer, read modeled flash, stream the exact data to a modeled JTAG target, verify IDCODE, and check host responses.
- [ ] Test reset and abort in every active phase; test invalid lengths, invalid memory types, divider boundaries, lane alignment, busy requests, and simultaneous status/error conditions.
- [ ] Run lint and synthesis using the selected FPGA toolchain. Resolve inferred-latch, multiple-driver, width, unsupported-construct, and timing warnings.
- [ ] Add pin constraints and clock/reset constraints for the chosen board; verify IO voltage, flash bus direction/tri-state behavior, JTAG timing, and SCLK limits on hardware.
- [ ] Record tested simulator/tool versions, supported flash/JTAG devices, parameter constraints, and known limitations in the main README before claiming release readiness.

## Current highest-priority blockers

1. The top-level does not connect flash data through DMA into JTAG, and DMA completion is tied low.
2. The JTAG path does not perform a real serial shift or target-driven IDCODE read.
3. The programmer FSM command semantics and start sequencing are incomplete.
4. The flash engine returns a bounded result register rather than a stream for a full bitstream.
5. There is no verified end-to-end programming test or hardware timing/sign-off.
