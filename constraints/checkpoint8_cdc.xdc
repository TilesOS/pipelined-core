# MIG's scoped XDC creates a primary clock at this hierarchical input pin.
# This pin receives the same board clock as the core/reference PLL, so replace
# that definition with an identity generated clock. Preserve its name and all
# MIG cell/pin timing constraints while restoring the common board-clock root.
set checkpoint8_mig_sys_pin [get_pins -quiet mig/ddr_probe_i/mig_7series_0/sys_clk_i]
if {[llength $checkpoint8_mig_sys_pin] != 1} {
    error "checkpoint 8 MIG system-clock pin not found"
}
create_generated_clock -name mig/ddr_probe_i/mig_7series_0/sys_clk_i \
    -source [get_ports sys_clk_i] -combinational $checkpoint8_mig_sys_pin

# The benchmark core clock and the MIG UI clock come from separate PLL/MMCM
# chains. AXI crosses between them only through rtl/bus/async_fifo.sv.
# Bound CDC path latency without assuming a stable phase relationship.
# 12 ns is below the faster (81.25 MHz) clock period of 12.308 ns, so the
# FIFO's Gray pointer and payload paths cannot trail a subsequent update.
set checkpoint8_core_clk [get_clocks -quiet -of_objects [get_pins clocks/pll/CLKOUT0]]
set checkpoint8_ui_clk [get_clocks -quiet -of_objects [get_pins \
    mig/ddr_probe_i/mig_7series_0/u_ddr_probe_mig_7series_0_0_mig/u_ddr2_infrastructure/gen_ui_extra_clocks.mmcm_i/CLKFBOUT]]
if {[llength $checkpoint8_core_clk] != 1 || [llength $checkpoint8_ui_clk] != 1} {
    error "checkpoint 8 CDC clocks not found: core=$checkpoint8_core_clk ui=$checkpoint8_ui_clk"
}
set_max_delay 12.000 -datapath_only -from $checkpoint8_core_clk -to $checkpoint8_ui_clk
set_max_delay 12.000 -datapath_only -from $checkpoint8_ui_clk -to $checkpoint8_core_clk
