set repo_root [file normalize [file join [file dirname [info script]] ..]]
set report_dir [file join $repo_root build checkpoint9-board vivado-reports]
file mkdir $report_dir
open_run synth_1
report_utilization -file [file join $report_dir synthesis_utilization.rpt]
report_utilization -hierarchical -file [file join $report_dir synthesis_hierarchy.rpt]
set ram_cells [get_cells -hier -quiet -filter {REF_NAME =~ RAMB*}]
set output [open [file join $report_dir synthesis_ram_cells.txt] w]
foreach cell $ram_cells {puts $output "$cell [get_property REF_NAME $cell]"}
close $output
puts "Block RAM primitives: [llength $ram_cells]"
set clock_port [get_ports sys_clk_i]
set clock_pin [get_property PACKAGE_PIN $clock_port]
set clock_standard [get_property IOSTANDARD $clock_port]
puts "Board clock pin: $clock_pin; IOSTANDARD: $clock_standard"
if {$clock_pin ne "E3" || $clock_standard ne "LVCMOS33"} {
    error "board clock must use E3/LVCMOS33 from checkpoint9_board.xdc"
}
foreach cache {icache dcache} {
    set cache_ram [get_cells -hier -quiet -filter "REF_NAME =~ RAMB* && NAME =~ system/cpu_system/cpu/$cache/*"]
    puts "$cache block RAM primitives: [llength $cache_ram]"
    if {[llength $cache_ram] == 0} {error "$cache data store did not map to block RAM"}
}
set cpu_dsp [get_cells -hier -quiet -filter {REF_NAME =~ DSP* && NAME =~ system/cpu_system/cpu/*}]
puts "CPU DSP primitives: [llength $cpu_dsp] (budget: 8)"
if {[llength $cpu_dsp] > 8} {error "CPU exceeds the DSP allocation"}
puts "Synthesis reports: $report_dir"
puts "Review cache RAM mapping and utilization before implementation."
