set repo_root [file normalize [file join [file dirname [info script]] ..]]
set report_dir [file join $repo_root build checkpoint10-board vivado-reports]
file mkdir $report_dir
open_run impl_1
report_io -file [file join $report_dir io.rpt]
if {[get_property PACKAGE_PIN [get_ports sys_clk_i]] ne "E3" ||
    [get_property IOSTANDARD [get_ports sys_clk_i]] ne "LVCMOS33"} {
    error "routed board clock must use E3/LVCMOS33"
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
puts "Checkpoint 10 implementation reports: $report_dir"
check_timing -verbose -file [file join $report_dir check_timing.rpt]
puts "Review new UART/button crossings and the loader ROM controls with the preserved FIFO/MIG diagnostics."
