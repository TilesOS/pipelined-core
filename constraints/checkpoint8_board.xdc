# Nexys A7-100T non-DDR pins from Digilent's master XDC. The generated MIG
# constraints own all DDR2 pins and timing; do not duplicate them here.
set_property -dict { PACKAGE_PIN E3 IOSTANDARD LVCMOS33 } [get_ports sys_clk_i]
create_clock -name board_clk_100 -period 10.000 [get_ports sys_clk_i]
set_property -dict { PACKAGE_PIN C12 IOSTANDARD LVCMOS33 } [get_ports CPU_RESETN]
set_property -dict { PACKAGE_PIN D4 IOSTANDARD LVCMOS33 } [get_ports UART_RXD_OUT]
set_property -dict { PACKAGE_PIN H17 IOSTANDARD LVCMOS33 } [get_ports {LED[0]}]
set_property -dict { PACKAGE_PIN K15 IOSTANDARD LVCMOS33 } [get_ports {LED[1]}]
set_property -dict { PACKAGE_PIN J13 IOSTANDARD LVCMOS33 } [get_ports {LED[2]}]
set_property -dict { PACKAGE_PIN N14 IOSTANDARD LVCMOS33 } [get_ports {LED[3]}]
