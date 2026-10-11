# Source only in the copied checkpoint10_board Vivado project.
set repo_root [file normalize [file join [file dirname [info script]] ..]]
set project_dir [file normalize [get_property DIRECTORY [current_project]]]
if {![string match *checkpoint10* [file tail $project_dir]]} {
    error "open a separate checkpoint10_board project copy first; current directory: $project_dir"
}
if {[string tolower [get_property PART [current_project]]] ne "xc7a100tcsg324-1"} {
    error "checkpoint 10 requires xc7a100tcsg324-1"
}
# Preparing BD ports regenerates the wrapper; never do this in checkpoint 9's
# original BD. Save Project As with source copying before running this script.
foreach bd [get_files -all -quiet *ddr_probe.bd] {
    if {![string match "${project_dir}/*" [file normalize $bd]]} {
        error "ddr_probe.bd still references $bd; copy/import the BD into $project_dir first"
    }
}
set image_dir [file join $repo_root build checkpoint10-board]
foreach name {checkpoint10_image.mem checkpoint10_image.svh image-manifest.json} {
    if {![file exists [file join $image_dir $name]]} {
        error "missing $name; run bash scripts/build_checkpoint10_board_image.sh first"
    }
}
source [file join $repo_root scripts/checkpoint8_prepare_bd.tcl]
foreach old_wrapper [get_files -all -quiet *ddr_probe_wrapper.v] {
    if {[file normalize $old_wrapper] ne [file normalize $wrapper_file]} {remove_files $old_wrapper}
}
set_property target_language Verilog [current_project]
set source_list [open [file join $repo_root scripts/checkpoint10_sources.txt] r]
set rtl_files [split [string trim [read $source_list]] "\n"]
close $source_list
foreach relative_path $rtl_files {
    set source_path [file join $repo_root $relative_path]
    if {![file exists $source_path]} {error "missing $source_path"}
    foreach existing [get_files -all -quiet *[file tail $relative_path]] {
        if {[file tail $existing] eq [file tail $relative_path] &&
            [file normalize $existing] ne [file normalize $source_path]} {remove_files $existing}
    }
    if {[llength [get_files -quiet $source_path]] == 0} {
        add_files -norecurse -fileset sources_1 $source_path
    }
}
# Remove project associations only; leave all original files/bitstreams intact.
foreach name {checkpoint8_board_top.sv checkpoint8_traffic.sv checkpoint8_uart_report.sv
              checkpoint9_board_top.sv checkpoint9_board_system.sv checkpoint9_smoke_mmio.sv
              checkpoint9_smoke_dma.sv checkpoint9_uart_report.sv checkpoint9_smoke.mem
              checkpoint8_vendor_stubs.sv} {
    foreach old [get_files -all -quiet *$name] {remove_files $old}
}
foreach name {checkpoint10_image.mem checkpoint10_image.svh} {
    set path [file join $image_dir $name]
    foreach old [get_files -all -quiet *$name] {
        if {[file normalize $old] ne [file normalize $path]} {remove_files $old}
    }
    if {[llength [get_files -quiet $path]] == 0} {add_files -norecurse $path}
}
set includes [get_property INCLUDE_DIRS [get_filesets sources_1]]
if {[lsearch -exact $includes $image_dir] < 0} {lappend includes $image_dir}
set_property INCLUDE_DIRS $includes [get_filesets sources_1]
foreach name {checkpoint8_board.xdc checkpoint8_cdc.xdc checkpoint9_board.xdc checkpoint9_cdc.xdc} {
    foreach old [get_files -all -quiet *$name] {
        set_property USED_IN_SYNTHESIS false $old
        set_property USED_IN_IMPLEMENTATION false $old
    }
}
foreach name {checkpoint10_board.xdc checkpoint10_cdc.xdc} {
    set path [file join $repo_root constraints $name]
    foreach old [get_files -all -quiet *$name] {
        if {[file normalize $old] ne [file normalize $path]} {remove_files $old}
    }
    if {[llength [get_files -quiet $path]] == 0} {add_files -norecurse -fileset constrs_1 $path}
}
set cdc_file [get_files [file join $repo_root constraints/checkpoint10_cdc.xdc]]
set_property FILE_TYPE Tcl $cdc_file
set_property USED_IN {implementation} $cdc_file
set_property USED_IN_SYNTHESIS false $cdc_file
set_property USED_IN_IMPLEMENTATION true $cdc_file
set_property PROCESSING_ORDER LATE $cdc_file
set board_file [get_files [file join $repo_root constraints/checkpoint10_board.xdc]]
set_property USED_IN_SYNTHESIS true $board_file
set_property USED_IN_IMPLEMENTATION true $board_file
if {[get_property USED_IN_SYNTHESIS $cdc_file] ||
    ![get_property USED_IN_IMPLEMENTATION $cdc_file] ||
    [lsearch -exact [get_property USED_IN $cdc_file] synthesis] >= 0} {
    error "checkpoint 10 CDC constraints must be implementation only"
}
set_property top checkpoint10_board_top [get_filesets sources_1]
update_compile_order -fileset sources_1
puts "Checkpoint 10 board sources installed from $repo_root"
puts "Reset impl_1 and synth_1, then rebuild; copied checkpoint 9 runs are stale."
