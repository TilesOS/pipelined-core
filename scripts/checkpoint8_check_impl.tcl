# Source in the Vivado Tcl Console after impl_1 finishes routing.
set repo_root [file normalize [file join [file dirname [info script]] ..]]
set report_dir [file join $repo_root build checkpoint8 vivado-reports]
file mkdir $report_dir
open_run impl_1
report_methodology -file [file join $report_dir methodology.rpt]
report_timing_summary -delay_type max -max_paths 5 -file [file join $report_dir timing_summary.rpt]
report_clocks -file [file join $report_dir clocks.rpt]
report_cdc -details -file [file join $report_dir cdc.rpt]
report_drc -file [file join $report_dir drc.rpt]
puts "Checkpoint 8 implementation reports: $report_dir"
