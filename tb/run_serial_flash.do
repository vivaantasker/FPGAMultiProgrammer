onerror {quit -f -code 1}
if {[file exists work]} {vdel -lib work -all}
vlib work
vlog -sv -timescale 1ns/1ps \
  ../rtl/common/programmer_pkg.sv \
  ../rtl/memory/spi_controller.sv \
  ../rtl/memory/serial_flash_read_engine.sv \
  ../rtl/memory/qspi_controller.sv \
  ../rtl/memory/ospi_controller.sv \
  ../rtl/memory/memory_manager.sv \
  tb_serial_flash_controllers.sv
vsim -c work.tb_serial_flash_controllers
run -all
quit -f
