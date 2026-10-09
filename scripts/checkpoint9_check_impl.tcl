set repo_root [file normalize [file join [file dirname [info script]] ..]]
set report_dir [file join $repo_root build checkpoint9-board vivado-reports]
file mkdir $report_dir
open_run impl_1
report_methodology -file [file join $report_dir methodology.rpt]
report_timing_summary -delay_type min_max -max_paths 20 -file [file join $report_dir timing_summary.rpt]
report_clocks -file [file join $report_dir clocks.rpt]
report_clock_interaction -file [file join $report_dir clock_interaction.rpt]
report_utilization -file [file join $report_dir utilization.rpt]
report_utilization -hierarchical -file [file join $report_dir hierarchy.rpt]
report_exceptions -file [file join $report_dir exceptions.rpt]
report_cdc -details -file [file join $report_dir cdc.rpt]
report_drc -file [file join $report_dir drc.rpt]
puts "Checkpoint 9 implementation reports: $report_dir"
