# Source once in the Vivado project containing the Nexys A7 MIG block design.
# The MIG is a child of ddr_probe.bd, so checkpoint8_board_top instantiates
# the block design wrapper rather than that child IP directly.
set bd_files {}
foreach candidate [get_files -all -quiet *.bd] {
    if {[file tail $candidate] eq "ddr_probe.bd"} {
        lappend bd_files $candidate
    }
}
if {[llength $bd_files] != 1} {
    error "expected exactly one ddr_probe.bd, found [llength $bd_files]"
}
set bd_file [lindex $bd_files 0]
open_bd_design $bd_file

set mig_cells {}
foreach cell [get_bd_cells -hier] {
    if {[string match *:mig_7series:* [get_property VLNV $cell]]} {
        lappend mig_cells $cell
    }
}
if {[llength $mig_cells] != 1} {
    error "expected one MIG cell in ddr_probe.bd, found [llength $mig_cells]"
}
set mig_cell [lindex $mig_cells 0]

set axi_pin [get_bd_intf_pins -quiet ${mig_cell}/S_AXI]
if {[llength $axi_pin] != 1} {error "MIG S_AXI interface not found"}
set axi_nets [get_bd_intf_nets -quiet -of_objects $axi_pin]
if {[llength $axi_nets] == 0} {
    make_bd_intf_pins_external $axi_pin
    set axi_nets [get_bd_intf_nets -of_objects $axi_pin]
}
set axi_ports [get_bd_intf_ports -quiet -of_objects $axi_nets]
if {[llength $axi_ports] != 1} {
    error "MIG S_AXI must connect to exactly one external interface port"
}
if {[get_property NAME [lindex $axi_ports 0]] ne "S_AXI"} {
    if {[llength [get_bd_intf_ports -quiet S_AXI]]} {
        error "an unrelated S_AXI external interface already exists"
    }
    set_property NAME S_AXI [lindex $axi_ports 0]
}

# Clock and DDR2 pins are already external in the Digilent board preset.
foreach pin_name {sys_rst aresetn ui_clk ui_clk_sync_rst init_calib_complete} {
    set pin [get_bd_pins -quiet ${mig_cell}/${pin_name}]
    if {[llength $pin] != 1} {error "MIG pin $pin_name not found"}
    set nets [get_bd_nets -quiet -of_objects $pin]
    if {[llength $nets] == 0} {
        make_bd_pins_external $pin
        set nets [get_bd_nets -of_objects $pin]
    }
    set ports [get_bd_ports -quiet -of_objects $nets]
    if {[llength $ports] != 1} {
        error "MIG pin $pin_name must connect to exactly one external port"
    }
    if {[get_property NAME [lindex $ports 0]] ne $pin_name} {
        if {[llength [get_bd_ports -quiet $pin_name]]} {
            error "an unrelated external port $pin_name already exists"
        }
        set_property NAME $pin_name [lindex $ports 0]
    }
}

validate_bd_design
save_bd_design
generate_target all $bd_file
set wrapper_file [make_wrapper -files $bd_file -top -force]
if {[llength [get_files -quiet $wrapper_file]] == 0} {
    add_files -norecurse -fileset sources_1 $wrapper_file
}
set_property top checkpoint8_board_top [get_filesets sources_1]
update_compile_order -fileset sources_1
puts "Checkpoint 8 BD prepared: $mig_cell, S_AXI, reset and UI ports"
puts "Wrapper: $wrapper_file"
puts "Top: [get_property top [get_filesets sources_1]]"
