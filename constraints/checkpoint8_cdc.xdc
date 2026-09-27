# The benchmark core clock and the MIG UI clock come from separate PLL/MMCM
# chains. AXI crosses between them only through rtl/bus/async_fifo.sv.
# Bound CDC path latency without assuming a stable phase relationship.
# 12 ns is below the faster (81.25 MHz) clock period of 12.308 ns, so the
# FIFO's Gray pointer and payload paths cannot trail a subsequent update.
set checkpoint8_core_clk [get_clocks -quiet clk50_unbuffered]
set checkpoint8_ui_clk [get_clocks -quiet clk_pll_i]
if {[llength $checkpoint8_core_clk] != 1 || [llength $checkpoint8_ui_clk] != 1} {
    error "checkpoint 8 CDC clocks not found: core=$checkpoint8_core_clk ui=$checkpoint8_ui_clk"
}
set_max_delay 12.000 -datapath_only -from $checkpoint8_core_clk -to $checkpoint8_ui_clk
set_max_delay 12.000 -datapath_only -from $checkpoint8_ui_clk -to $checkpoint8_core_clk
