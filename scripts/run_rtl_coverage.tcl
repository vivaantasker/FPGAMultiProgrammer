# Run from the Vivado Tcl Console with the intended project open.
# Adds the package and focused coverage harness, selects tb_rtl_coverage,
# then launches XSim. The existing integrated simulation set is left alone.

if {[current_project -quiet] eq ""} {
    error "No Vivado project is open. Open the .xpr first, then source this script."
}

set script_dir [file dirname [file normalize [info script]]]
set package_root [file normalize [file join $script_dir ..]]
set rtl_root [file join $package_root rtl]
set tb_root [file join $package_root tb]
set sim_name "sim_rtl_coverage"

if {[llength [get_filesets -quiet $sim_name]] == 0} {
    create_fileset -simset $sim_name
}

proc coverage_add_if_missing {fileset path} {
    set path [file normalize $path]
    set already_added 0
    foreach existing [get_files -quiet -of_objects [get_filesets $fileset]] {
        if {[file normalize $existing] eq $path} {
            set already_added 1
            break
        }
    }
    if {!$already_added} {
        add_files -norecurse -fileset $fileset $path
        puts "Added to $fileset : $path"
    } else {
        puts "Already present in $fileset : $path"
    }
}

set rtl_files [list \
    [file join $rtl_root common programmer_pkg.sv] \
    [file join $rtl_root controller interrupt_controller.sv] \
    [file join $rtl_root scheduler axi_lite_write_master.sv] \
    [file join $rtl_root scheduler time_multiplex_scheduler.sv] \
]
foreach f $rtl_files {
    if {![file exists $f]} { error "Missing RTL source: $f" }
    coverage_add_if_missing sources_1 $f
}

set tb_file [file join $tb_root tb_rtl_coverage.sv]
if {![file exists $tb_file]} { error "Missing coverage testbench: $tb_file" }
coverage_add_if_missing $sim_name $tb_file
set_property top tb_rtl_coverage [get_filesets $sim_name]
set_property top_lib xil_defaultlib [get_filesets $sim_name]
update_compile_order -fileset sources_1
update_compile_order -fileset $sim_name
current_fileset -sim $sim_name

puts "Launching focused RTL functional coverage simulation..."
launch_simulation -simset $sim_name
