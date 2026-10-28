onerror {quit -f -code 1}
if {[file exists work]} {vdel -lib work -all}
vlib work
vlog -sv -timescale 1ns/1ps \
  ../rtl/common/programmer_pkg.sv \
  ../rtl/jtag/jtag_tap.sv \
  ../rtl/jtag/jtag_shift_engine.sv \
  ../rtl/jtag/jtag_clock.sv \
  jtag_if.sv \
  jtag_env_pkg.sv \
  tb_jtag.sv
vsim -c work.tb_jtag
run -all
quit -f
