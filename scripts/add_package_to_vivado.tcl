# add_package_to_vivado.tcl
# Run this from Vivado Tcl Console with the desired project OPEN.
# It adds the packaged RTL and the integrated testbench/model sources.
# Safe to rerun: checks whether each normalized source path is already added.

set script_dir [file dirname [file normalize [info script]]]
set package_root [file normalize [file join $script_dir ..]]
set rtl_root [file join $package_root rtl]
set tb_root  [file join $package_root tb]

if {[current_project -quiet] eq ""} {
    error "No Vivado project is open. Open your .xpr first, then source this script."
}

# Use existing sim_multi_image_schedule fileset if present; create if absent.
set sim_name "sim_multi_image_schedule"
set sim_fs [get_filesets -quiet $sim_name]
if {[llength $sim_fs] == 0} {
    create_fileset -simset $sim_name
    set sim_fs [get_filesets $sim_name]
}

proc add_if_missing {fileset path} {
    set path [file normalize $path]
    set already [get_files -quiet -of_objects [get_filesets $fileset] $path]
    if {[llength $already] == 0} {
        add_files -norecurse -fileset $fileset $path
        puts "Added to $fileset : $path"
    } else {
        puts "Already present in $fileset : $path"
    }
}

# RTL sources from the active design hierarchy (13 files).
set rtl_files [list \
    [file join $rtl_root scheduler axi_lite_write_master.sv] \
    [file join $rtl_root dma dma_controller.sv] \
    [file join $rtl_root common programmer_pkg.sv] \
    [file join $rtl_root controller interrupt_controller.sv] \
    [file join $rtl_root jtag jtag_controller.sv] \
    [file join $rtl_root memory memory_manager.sv] \
    [file join $rtl_root memory ospi_controller.sv] \
    [file join $rtl_root axi programmer_control_regs_axi.sv] \
    [file join $rtl_root memory qspi_controller.sv] \
    [file join $rtl_root memory serial_flash_read_engine.sv] \
    [file join $rtl_root memory spi_controller.sv] \
    [file join $rtl_root scheduler time_multiplex_scheduler.sv] \
    [file join $rtl_root top fpga_multiphase_reconfig_top.sv] \
]

foreach f $rtl_files {
    if {![file exists $f]} { error "Missing packaged RTL source: $f" }
    add_if_missing sources_1 $f
}

# Integrated simulation top and its two behavioral models.
set tb_files [list \
    [file join $tb_root tb_multi_image_schedule.sv] \
    [file join $tb_root models jtag_target_model.sv] \
    [file join $tb_root models qspi_nor_multi_image_model.sv] \
]
foreach f $tb_files {
    if {![file exists $f]} { error "Missing packaged simulation source: $f" }
    add_if_missing $sim_name $f
}

# Ensure SystemVerilog is used and set the simulation top.
set_property file_type SystemVerilog [get_files -of_objects [get_filesets sources_1] $rtl_files]
set_property top tb_multi_image_schedule [get_filesets $sim_name]
set_property top_lib xil_defaultlib [get_filesets $sim_name]

# Recompute compile order, select this simulation set, and launch.
update_compile_order -fileset sources_1
update_compile_order -fileset $sim_name
current_fileset -sim $sim_name

puts "\nPackage sources added. Launching integrated simulation..."
launch_simulation -simset $sim_name
