# Usage: vivado -mode batch -source scripts/checkpoint8_reports.tcl \
#          -tclargs /absolute/path/to/project.xpr /absolute/path/to/reports
if {$argc != 2} {
    error "expected project.xpr and output directory"
}
set project_path [file normalize [lindex $argv 0]]
set report_dir [file normalize [lindex $argv 1]]
file mkdir $report_dir
open_project $project_path
open_run impl_1
report_timing_summary -delay_type max -max_paths 20 -file [file join $report_dir timing_summary.rpt]
report_utilization -file [file join $report_dir utilization.rpt]
report_clocks -file [file join $report_dir clocks.rpt]
report_clock_interaction -file [file join $report_dir clock_interaction.rpt]
report_drc -file [file join $report_dir drc.rpt]
puts "Checkpoint 8 reports written to $report_dir"
