# FPGA Programmer: Multi-Image Reconfiguration RTL

This repository contains an RTL platform for sequencing configuration of multiple FPGA images stored in serial flash. The design coordinates metadata parsing, AXI4-Lite peripheral setup, AXI4-Stream image movement, JTAG programming, and target task-completion/error events.

## Architecture

The scheduler reads image metadata from the memory manager, configures the peripherals through the AXI4-Lite register aperture, and advances between images after target events. Metadata stream data goes directly to the scheduler; image data flows through the DMA bridge to the JTAG controller.

```mermaid
flowchart LR
    START([schedule_start]) --> SCHED[time_multiplex_scheduler]
    SCHED <-->|AXI4-Lite control| REGS[programmer_control_regs_axi]
    REGS -->|memory controls| MEM[memory_manager]
    REGS -->|DMA controls| DMA[dma_controller]
    REGS -->|JTAG controls| JTAG[jtag_controller]

    MEM -->|metadata stream in metadata mode| SCHED
    MEM -->|image AXI-Stream| DMA
    DMA -->|image AXI-Stream| JTAG
    MEM --> IFACE{Selected flash interface}
    IFACE --> SPI[SPI]
    IFACE --> QSPI[QSPI]
    IFACE --> OSPI[OSPI]

    JTAG -->|TCK / TMS / TDI| TAP[Target FPGA TAP]
    TAP -->|TDO| JTAG

    TARGET_STATUS[Target configuration status] --> SYNC[Two-flop synchronizers]
    TARGET_EVENTS[Target task done / error] --> SYNC
    SYNC -->|configuration status| SCHED
    SYNC -->|task events| IRQ[interrupt_controller]

    MEM -.->|done / error| IRQ
    DMA -.->|done / error| IRQ
    JTAG -.->|done / error / IDCODE ready| IRQ
    IRQ -->|irq status| SCHED
    SCHED -->|interrupt clear requests| IRQ

    PKG[programmer_pkg] -.->|shared types and constants| SCHED
    PKG -.->|shared types and constants| REGS
    PKG -.->|shared types and constants| MEM
    PKG -.->|shared types and constants| JTAG
```

The top-level RTL currently selects the QSPI path. SPI and OSPI interfaces are also exposed by the memory manager. The target FPGA is external to this RTL: the top-level accepts configuration-status and task-event inputs and provides the JTAG pins.

## Repository layout

| Path | Purpose |
| --- | --- |
| `rtl/common/` | Shared package definitions and helper functions |
| `rtl/top/` | Top-level multi-phase reconfiguration design |
| `rtl/scheduler/` | Schedule sequencer and AXI4-Lite write master |
| `rtl/axi/` | AXI4-Lite programmer control register block |
| `rtl/memory/` | Memory manager and SPI, QSPI, OSPI, and flash-read RTL |
| `rtl/dma/` | AXI4-Stream DMA bridge |
| `rtl/jtag/` | JTAG TAP controller |
| `rtl/controller/` | Interrupt controller |
| `tb/tb_multi_image_schedule.sv` | Integrated three-image testbench source |
| `tb/tb_rtl_coverage.sv` | Focused package, interrupt, and scheduler testbench |
| `tb/models/` | Behavioral multi-image QSPI flash and JTAG target models |
| `scripts/` | Vivado Tcl setup and simulation scripts |

## Vivado simulation

### Integrated multi-image testbench

The integrated testbench top is `tb_multi_image_schedule`. Add the RTL under `rtl/` to the design source set, then add these simulation sources to a simulation set:

- `tb/tb_multi_image_schedule.sv`
- `tb/models/qspi_nor_multi_image_model.sv`
- `tb/models/jtag_target_model.sv`

Compile `rtl/common/programmer_pkg.sv` before modules that import it, use SystemVerilog mode, and set `tb_multi_image_schedule` as the simulation top. The testbench source contains checks for a nominal three-image QSPI-to-JTAG flow. Those checks are not evidence of a successful integrated run unless the corresponding XSim transcript is available.

With the intended Vivado project open, the helper script can add the package sources and launch the integrated simulation. Update the path for your checkout:

```tcl
source C:/path/to/ASIC_Project/scripts/add_package_to_vivado.tcl
```

### Focused RTL testbench

The focused testbench targets `programmer_pkg`, `interrupt_controller`, and `time_multiplex_scheduler`. It checks package constants, enum values and CRC helper behavior; exercises interrupt capture, masking, sticky status and clearing; and drives a scheduler AXI write-error/abort scenario.

With the project open in Vivado, run:

```tcl
source C:/path/to/ASIC_Project/scripts/run_rtl_coverage.tcl
```

The script creates or reuses `sim_rtl_coverage`, adds the focused testbench and its required RTL, sets `tb_rtl_coverage` as simulation top, updates compile order, and launches XSim. This testbench is separate from the integrated simulation set.

## Focused run results and coverage status

The supplied Vivado XSim transcript reported:

| Target | Reported checks / scenarios |
| --- | ---: |
| `programmer_pkg` | 94 checked cases |
| `interrupt_controller` | 12 checked scenarios |
| `time_multiplex_scheduler` | 3 checked scenarios |
| Scoreboard | 29 checks |
| Simulation | Reached `$finish` at 390 ns without a testbench failure |

These are directed testbench check and scenario counts. They are **not** code-coverage or functional-coverage percentages. Although the current focused testbench contains SystemVerilog covergroups, the supplied successful transcript predates their addition. The subsequent `xcrg` attempt reported that no functional coverage database was found, so no XCRG percentage, bin total, or cross-coverage result is available. Rerun the simulation with recognized covergroups or enabled code coverage, confirm an XSim coverage database is created, and then run XCRG before reporting percentages.

The integrated testbench also defines executable nominal-flow checks. Treat those as testbench expectations until a successful integrated XSim run log is archived.

## Verification flow

The two benches have different scopes. The focused bench checks selected package, interrupt, and scheduler behavior. The integrated bench connects the top-level RTL to behavioral flash and JTAG target models.

```mermaid
flowchart TB
    subgraph FOCUSED["Focused RTL simulation"]
        FTB[tb_rtl_coverage]
        FTB --> PKG[programmer_pkg checks]
        FTB --> IRQ[interrupt_controller scenarios]
        FTB --> SCH[time_multiplex_scheduler AXI error and abort]
        PKG --> COUNTS[Directed check counters]
        IRQ --> COUNTS
        SCH --> COUNTS
    end

    subgraph INTEGRATED["Integrated simulation"]
        ITB[tb_multi_image_schedule]
        ITB --> DUT[fpga_multiphase_reconfig_top]
        ITB --> FLASH[qspi_nor_multi_image_model]
        ITB --> JT[jtag_target_model]
        FLASH <--> DUT
        JT <--> DUT
        DUT --> EXPECT[Nominal-flow pass/fail checks]
    end

    COUNTS --> CAVEAT[Counts are not coverage percentages]
    XCRG[XCRG report request] --> DB{Coverage database found?}
    DB -->|No in supplied attempt| PENDING[XCRG coverage unavailable]
    DB -->|Yes after a future rerun| REPORT[Generate and review coverage report]
```

## Waveforms and hardware scope

A `.wcfg` file stores a waveform viewer layout; it is not the waveform trace. Save a configuration from Vivado with **File → Save Waveform Configuration As** if you want to preserve a signal layout. Simulation traces are generated by rerunning XSim.

This package documents RTL simulation with behavioral flash and JTAG target models. It does not establish physical-board operation, bitstream correctness on a target device, synthesis utilization, or timing closure.
