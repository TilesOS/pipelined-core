// Port-only stand-ins for linting the board top without Vivado libraries.
// Never add this file to a synthesis project.
module PLLE2_BASE #(
    parameter BANDWIDTH = "OPTIMIZED",
    parameter integer CLKFBOUT_MULT = 1,
    parameter real CLKFBOUT_PHASE = 0.0,
    parameter real CLKIN1_PERIOD = 0.0,
    parameter integer CLKOUT0_DIVIDE = 1,
    parameter real CLKOUT0_DUTY_CYCLE = 0.5,
    parameter real CLKOUT0_PHASE = 0.0,
    parameter integer CLKOUT1_DIVIDE = 1,
    parameter real CLKOUT1_DUTY_CYCLE = 0.5,
    parameter real CLKOUT1_PHASE = 0.0,
    parameter integer DIVCLK_DIVIDE = 1,
    parameter real REF_JITTER1 = 0.010
) (
    input wire CLKIN1, CLKFBIN, PWRDWN, RST,
    output wire CLKFBOUT, CLKOUT0, CLKOUT1, CLKOUT2,
    output wire CLKOUT3, CLKOUT4, CLKOUT5, LOCKED
);
endmodule

module BUFG(input wire I, output wire O);
endmodule

module ddr_probe_wrapper (
    output wire [12:0] ddr2_sdram_addr,
    output wire [2:0] ddr2_sdram_ba,
    output wire ddr2_sdram_cas_n,
    output wire [0:0] ddr2_sdram_ck_n, ddr2_sdram_ck_p, ddr2_sdram_cke,
    output wire ddr2_sdram_ras_n, ddr2_sdram_we_n,
    inout wire [15:0] ddr2_sdram_dq,
    inout wire [1:0] ddr2_sdram_dqs_n, ddr2_sdram_dqs_p,
    output wire init_calib_complete,
    output wire [0:0] ddr2_sdram_cs_n, ddr2_sdram_odt,
    output wire [1:0] ddr2_sdram_dm,
    output wire ui_clk, ui_clk_sync_rst,
    input wire aresetn,
    input wire [3:0] S_AXI_awid,
    input wire [26:0] S_AXI_awaddr,
    input wire [7:0] S_AXI_awlen,
    input wire [2:0] S_AXI_awsize,
    input wire [1:0] S_AXI_awburst,
    input wire [0:0] S_AXI_awlock,
    input wire [3:0] S_AXI_awcache,
    input wire [2:0] S_AXI_awprot,
    input wire [3:0] S_AXI_awqos,
    input wire S_AXI_awvalid,
    output wire S_AXI_awready,
    input wire [127:0] S_AXI_wdata,
    input wire [15:0] S_AXI_wstrb,
    input wire S_AXI_wlast, S_AXI_wvalid,
    output wire S_AXI_wready,
    output wire [3:0] S_AXI_bid,
    output wire [1:0] S_AXI_bresp,
    output wire S_AXI_bvalid,
    input wire S_AXI_bready,
    input wire [3:0] S_AXI_arid,
    input wire [26:0] S_AXI_araddr,
    input wire [7:0] S_AXI_arlen,
    input wire [2:0] S_AXI_arsize,
    input wire [1:0] S_AXI_arburst,
    input wire [0:0] S_AXI_arlock,
    input wire [3:0] S_AXI_arcache,
    input wire [2:0] S_AXI_arprot,
    input wire [3:0] S_AXI_arqos,
    input wire S_AXI_arvalid,
    output wire S_AXI_arready,
    output wire [3:0] S_AXI_rid,
    output wire [127:0] S_AXI_rdata,
    output wire [1:0] S_AXI_rresp,
    output wire S_AXI_rlast, S_AXI_rvalid,
    input wire S_AXI_rready,
    input wire sys_clk_i, clk_ref_i, sys_rst
);
endmodule
