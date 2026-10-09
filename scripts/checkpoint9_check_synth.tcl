set repo_root [file normalize [file join [file dirname [info script]] ..]]
set report_dir [file join $repo_root build checkpoint9-board vivado-reports]
file mkdir $report_dir
open_run synth_1
report_utilization -file [file join $report_dir synthesis_utilization.rpt]
report_utilization -hierarchical -file [file join $report_dir synthesis_hierarchy.rpt]
set ram_cells [get_cells -hier -filter {REF_NAME =~ RAMB*}]
set output [open [file join $report_dir synthesis_ram_cells.txt] w]
foreach cell $ram_cells {puts $output "$cell [get_property REF_NAME $cell]"}
close $output
puts "Block RAM primitives: [llength $ram_cells]"
puts "Synthesis reports: $report_dir"
puts "Review cache RAM mapping and utilization before implementation."
