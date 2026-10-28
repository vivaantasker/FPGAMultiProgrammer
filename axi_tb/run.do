onerror {quit -f -code 1}
if {[file exists work]} {vdel -lib work -all}
vlib work
vlog -sv -timescale 1ns/1ps \
  ../rtl/axi/axi_lite_master.sv \
  axi_lite_if.sv \
  axi_env_pkg.sv \
  tb_axi_lite_master.sv
vsim -c work.tb_axi_lite_master
run -all
quit -f
