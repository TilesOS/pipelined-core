# Source in a COPY of the working checkpoint 8 Vivado project.
set repo_root [file normalize [file join [file dirname [info script]] ..]]
if {[string tolower [get_property PART [current_project]]] ne "xc7a100tcsg324-1"} {
    error "checkpoint 9 requires xc7a100tcsg324-1"
}
# Reuse the proven MIG wrapper ports; this script briefly sets the old top.
source [file join $repo_root scripts/checkpoint8_prepare_bd.tcl]
foreach old_wrapper [get_files -all -quiet *ddr_probe_wrapper.v] {
    if {[file normalize $old_wrapper] ne [file normalize $wrapper_file]} {
        remove_files $old_wrapper
    }
}
set_property target_language Verilog [current_project]
set rtl_files [list \
    rtl/bus/axi128_pkg.sv rtl/cache/physical_memory_pkg.sv \
    rtl/bus/async_fifo.sv rtl/bus/axi_cdc.sv rtl/bus/axi_fabric.sv \
    rtl/bus/axi_subsystem.sv rtl/bus/axi_width_bridge.sv \
    rtl/bus/axi_peripheral_adapter.sv rtl/cache/l1_cache.sv \
    rtl/core/rv32_slice.sv rtl/debug/uart_tx_byte.sv rtl/debug/trace_ring_uart.sv \
    rtl/top/rv32_cached_core.sv rtl/top/checkpoint9_top.sv \
    rtl/top/checkpoint8_core_clock.sv rtl/top/checkpoint9_smoke_mmio.sv \
    rtl/top/checkpoint9_smoke_dma.sv rtl/top/checkpoint9_uart_report.sv \
    rtl/top/checkpoint9_board_system.sv rtl/top/checkpoint9_board_top.sv \
    config/rom/checkpoint9_smoke.mem]
foreach relative_path $rtl_files {
    set source_path [file join $repo_root $relative_path]
    if {![file exists $source_path]} {error "missing $source_path"}
    # Save Project As may retain imported RTL copies. Replace their project
    # associations with the checked-out source, preserving the files on disk.
    foreach existing [get_files -all -quiet *[file tail $relative_path]] {
        if {[file tail $existing] eq [file tail $relative_path] &&
            [file normalize $existing] ne [file normalize $source_path]} {
            remove_files $existing
        }
    }
    if {[llength [get_files -quiet $source_path]] == 0} {
        add_files -norecurse -fileset sources_1 $source_path
    }
}
foreach name {checkpoint8_board.xdc checkpoint8_cdc.xdc} {
    foreach old [get_files -all -quiet *$name] {
        set_property USED_IN_SYNTHESIS false $old
        set_property USED_IN_IMPLEMENTATION false $old
    }
}
foreach name {checkpoint9_board.xdc checkpoint9_cdc.xdc} {
    set path [file join $repo_root constraints $name]
    if {[llength [get_files -quiet $path]] == 0} {
        add_files -norecurse -fileset constrs_1 $path
    }
}
# The clock-object guards use Tcl conditionals, which managed XDC rejects.
# Vivado supports Tcl constraint files in constrs_1; preserve late ordering
# and fail explicitly if the expected MIG/core clock objects are missing.
set cdc_file [get_files [file join $repo_root constraints/checkpoint9_cdc.xdc]]
set_property FILE_TYPE Tcl $cdc_file
# Apply usage AFTER the file type. MIG is a black box during top synthesis;
# its internal clock pins become available when the IP DCP is linked.
set_property USED_IN {implementation} $cdc_file
set_property USED_IN_SYNTHESIS false $cdc_file
set_property USED_IN_IMPLEMENTATION true $cdc_file
set_property PROCESSING_ORDER LATE $cdc_file
set board_file [get_files [file join $repo_root constraints/checkpoint9_board.xdc]]
set_property USED_IN_SYNTHESIS true $board_file
set_property USED_IN_IMPLEMENTATION true $board_file
if {[get_property USED_IN_SYNTHESIS $cdc_file] ||
    ![get_property USED_IN_IMPLEMENTATION $cdc_file] ||
    [lsearch -exact [get_property USED_IN $cdc_file] synthesis] >= 0} {
    error "checkpoint 9 CDC constraints must be implementation only"
}
puts "CDC constraint usage: [get_property USED_IN $cdc_file]; synthesis: [get_property USED_IN_SYNTHESIS $cdc_file]"
set_property top checkpoint9_board_top [get_filesets sources_1]
update_compile_order -fileset sources_1
puts "Checkpoint 9 ROM/CPU/cache board top ready: [get_property top [get_filesets sources_1]]"
puts "Run synthesis first, then source [file join $repo_root scripts/checkpoint9_check_synth.tcl]"
