# Source this in the open Vivado project that contains ddr_probe.bd.
# Example: source /path/to/pipelined-core/scripts/checkpoint8_add_sources.tcl
set repo_root [file normalize [file join [file dirname [info script]] ..]]
if {[string tolower [get_property PART [current_project]]] ne "xc7a100tcsg324-1"} {
    error "checkpoint 8 requires xc7a100tcsg324-1"
}
set_property target_language Verilog [current_project]
set rtl_files [list \
    rtl/bus/axi128_pkg.sv \
    rtl/bus/async_fifo.sv \
    rtl/bus/axi_cdc.sv \
    rtl/bus/axi_fabric.sv \
    rtl/bus/axi_subsystem.sv \
    rtl/debug/uart_tx_byte.sv \
    rtl/top/checkpoint8_core_clock.sv \
    rtl/top/checkpoint8_traffic.sv \
    rtl/top/checkpoint8_uart_report.sv \
    rtl/top/checkpoint8_board_top.sv]
foreach relative_path $rtl_files {
    set source_path [file join $repo_root $relative_path]
    if {![file exists $source_path]} {error "missing $source_path"}
    if {[llength [get_files -quiet $source_path]] == 0} {
        add_files -norecurse -fileset sources_1 $source_path
    }
}
set xdc_path [file join $repo_root constraints/checkpoint8_board.xdc]
if {[llength [get_files -quiet $xdc_path]] == 0} {
    add_files -norecurse -fileset constrs_1 $xdc_path
}
set cdc_path [file join $repo_root constraints/checkpoint8_cdc.xdc]
if {[llength [get_files -quiet $cdc_path]] == 0} {
    add_files -norecurse -fileset constrs_1 $cdc_path
}
# The MIG creates clk_pll_i in its generated XDC. Read this file afterwards.
set_property PROCESSING_ORDER LATE [get_files $cdc_path]
set_property USED_IN_SYNTHESIS false [get_files $cdc_path]
set_property top checkpoint8_board_top [get_filesets sources_1]
update_compile_order -fileset sources_1
puts "Checkpoint 8 RTL and constraints added from $repo_root"
puts "Top: [get_property top [get_filesets sources_1]]"
puts "Next: source [file join $repo_root scripts/checkpoint8_prepare_bd.tcl]"
