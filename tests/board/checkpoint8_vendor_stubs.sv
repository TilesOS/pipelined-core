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

module ddr_probe_mig_7series_0_0 (
    output wire [12:0] ddr2_addr,
    output wire [2:0] ddr2_ba,
    output wire ddr2_cas_n,
    output wire [0:0] ddr2_ck_n, ddr2_ck_p, ddr2_cke,
    output wire ddr2_ras_n, ddr2_we_n,
    inout wire [15:0] ddr2_dq,
    inout wire [1:0] ddr2_dqs_n, ddr2_dqs_p,
    output wire init_calib_complete,
    output wire [0:0] ddr2_cs_n, ddr2_odt,
    output wire [1:0] ddr2_dm,
    output wire ui_clk, ui_clk_sync_rst,
    output wire ui_addn_clk_0, ui_addn_clk_1, ui_addn_clk_2,
    output wire ui_addn_clk_3, ui_addn_clk_4,
    output wire mmcm_locked, app_sr_active, app_ref_ack, app_zq_ack,
    input wire aresetn,
    input wire [3:0] s_axi_awid,
    input wire [26:0] s_axi_awaddr,
    input wire [7:0] s_axi_awlen,
    input wire [2:0] s_axi_awsize,
    input wire [1:0] s_axi_awburst,
    input wire [0:0] s_axi_awlock,
    input wire [3:0] s_axi_awcache,
    input wire [2:0] s_axi_awprot,
    input wire [3:0] s_axi_awqos,
    input wire s_axi_awvalid,
    output wire s_axi_awready,
    input wire [127:0] s_axi_wdata,
    input wire [15:0] s_axi_wstrb,
    input wire s_axi_wlast, s_axi_wvalid,
    output wire s_axi_wready,
    output wire [3:0] s_axi_bid,
    output wire [1:0] s_axi_bresp,
    output wire s_axi_bvalid,
    input wire s_axi_bready,
    input wire [3:0] s_axi_arid,
    input wire [26:0] s_axi_araddr,
    input wire [7:0] s_axi_arlen,
    input wire [2:0] s_axi_arsize,
    input wire [1:0] s_axi_arburst,
    input wire [0:0] s_axi_arlock,
    input wire [3:0] s_axi_arcache,
    input wire [2:0] s_axi_arprot,
    input wire [3:0] s_axi_arqos,
    input wire s_axi_arvalid,
    output wire s_axi_arready,
    output wire [3:0] s_axi_rid,
    output wire [127:0] s_axi_rdata,
    output wire [1:0] s_axi_rresp,
    output wire s_axi_rlast, s_axi_rvalid,
    input wire s_axi_rready,
    input wire sys_clk_i, clk_ref_i, sys_rst
);
endmodule
