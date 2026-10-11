set repo_root [file normalize [file join [file dirname [info script]] ..]]
set report_dir [file join $repo_root build checkpoint10-board vivado-reports]
file mkdir $report_dir
set source_state [open [file join $report_dir implementation_source.txt] w]
puts $source_state "Implementation source commit: [exec git -C $repo_root rev-parse HEAD]"
puts $source_state "Implementation source dirty: [expr {[string trim [exec git -C $repo_root status --porcelain]] ne {}}]"
puts $source_state "Image/synthesis source identity: see the retained image-manifest.json"
close $source_state
open_run impl_1
report_io -file [file join $report_dir io.rpt]
if {[get_property PACKAGE_PIN [get_ports sys_clk_i]] ne "E3" ||
    [get_property IOSTANDARD [get_ports sys_clk_i]] ne "LVCMOS33"} {
    error "routed board clock must use E3/LVCMOS33"
}
set cpu_reset_regs [get_cells -hier -quiet -filter {REF_NAME =~ FD* && NAME =~ board/system/system/*cpu_reset_n_reg*}]
set reset_report [open [file join $report_dir cpu_reset_cells.txt] w]
foreach cell $cpu_reset_regs {puts $reset_report "$cell [get_property REF_NAME $cell]"}
close $reset_report
puts "Registered CPU reset primitives: [llength $cpu_reset_regs]"
if {[llength $cpu_reset_regs] == 0} {error "registered CPU reset is missing; verify fresh checkpoint 10 implementation"}
foreach cell $cpu_reset_regs {
    if {[get_property REF_NAME $cell] ne "FDRE"} {
        error "CPU reset must use a clocked FDRE without asynchronous control; verify fresh checkpoint 10 implementation"
    }
}
report_methodology -file [file join $report_dir methodology.rpt]
report_timing_summary -delay_type min_max -max_paths 20 -file [file join $report_dir timing_summary.rpt]
report_clocks -file [file join $report_dir clocks.rpt]
report_clock_interaction -file [file join $report_dir clock_interaction.rpt]
report_utilization -file [file join $report_dir utilization.rpt]
report_utilization -hierarchical -file [file join $report_dir hierarchy.rpt]
set cpu_primitives [get_cells -quiet -hierarchical -filter {IS_PRIMITIVE == 1 && NAME =~ board/system/system/cpu/*}]
set cpu_slice_sites [lsort -unique [get_sites -quiet -of_objects $cpu_primitives -filter {SITE_TYPE =~ SLICE*}]]
set area_report [open [file join $report_dir cpu_cache_area.txt] w]
puts $area_report "CPU/cache occupied slice sites: [llength $cpu_slice_sites]"
puts $area_report "Budget: 3000 slice sites; overage: [expr {max(0, [llength $cpu_slice_sites] - 3000)}]"
close $area_report
puts "CPU/cache occupied slice sites: [llength $cpu_slice_sites] (budget 3000)"
report_exceptions -file [file join $report_dir exceptions.rpt]
report_cdc -details -file [file join $report_dir cdc.rpt]
report_drc -file [file join $report_dir drc.rpt]
if {[catch {report_power_opt -file [file join $report_dir power_opt.rpt]} power_report_error]} {
    set power_report [open [file join $report_dir power_opt.rpt] w]
    puts $power_report "Power optimization report unavailable: $power_report_error"
    close $power_report
}
set tag_controls [open [file join $report_dir tag_ram_controls.txt] w]
set tag_enable_pins [get_pins -hier -quiet -filter {NAME =~ board/system/system/cpu/icache/tags*_reg/ENARDEN}]
if {[llength $tag_enable_pins] != 2} {
    close $tag_controls
    error "checkpoint 10 expects two I-cache tag RAM enable pins for control review"
}
foreach pin $tag_enable_pins {
    puts $tag_controls $pin
    puts $tag_controls "STARTPOINTS: [all_fanin -flat -startpoints_only -to $pin]"
}
close $tag_controls
puts "Checkpoint 10 implementation reports: $report_dir"
check_timing -verbose -file [file join $report_dir check_timing.rpt]
puts "Review new UART/button crossings and the loader ROM controls with the preserved FIFO/MIG diagnostics."
set drc_file [open [file join $report_dir drc.rpt] r]
set drc_text [read $drc_file]
close $drc_file
if {[regexp -line {^REQP-18(39|40)#[0-9]+\s} $drc_text]} {
    error "RAM asynchronous-control warnings remain; review drc.rpt and tag_ram_controls.txt before a bitstream"
}
