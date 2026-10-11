`timescale 1ns/1ps
// Checkpoint 10 board proof; image header is generated under build/checkpoint10-board.
`include "checkpoint10_image.svh"
module checkpoint10_board_top (
    input  wire        sys_clk_i,
    input  wire        CPU_RESETN,
    input  wire        UART_TXD_IN,
    input  wire        BTNC,
    output wire        UART_RXD_OUT,
    output wire [3:0]  LED,
    output wire [12:0] ddr2_addr,
    output wire [2:0]  ddr2_ba,
    output wire        ddr2_cas_n,
    output wire [0:0]  ddr2_ck_n,
    output wire [0:0]  ddr2_ck_p,
    output wire [0:0]  ddr2_cke,
    output wire        ddr2_ras_n,
    output wire        ddr2_we_n,
    inout  wire [15:0] ddr2_dq,
    inout  wire [1:0]  ddr2_dqs_n,
    inout  wire [1:0]  ddr2_dqs_p,
    output wire [0:0]  ddr2_cs_n,
    output wire [1:0]  ddr2_dm,
    output wire [0:0]  ddr2_odt
);
    import axi128_pkg::*;
    wire core_clk, ref_clk_200, core_pll_locked;
    wire ui_clk, ui_clk_sync_rst, init_calib_complete, mig_axi_resetn;
    axi_req_t mig_req;
    axi_rsp_t mig_rsp;
    (* mark_debug = "true" *) wire [31:0] last_pc, last_cause, last_tval;
    checkpoint8_core_clock clocks (
        .clk100(sys_clk_i), .rst_n(CPU_RESETN), .clk50(core_clk),
        .clk200(ref_clk_200), .locked(core_pll_locked)
    );
    assign mig_axi_resetn = !ui_clk_sync_rst;
    checkpoint10_board_system #(
        .IMAGE_WORDS(`CHECKPOINT10_IMAGE_WORDS), .ROM_WORDS(`CHECKPOINT10_ROM_WORDS),
        .FIRMWARE_WORDS(`CHECKPOINT10_FIRMWARE_WORDS), .PAYLOAD_WORD(`CHECKPOINT10_PAYLOAD_WORD),
        .IMAGE_FILE(`CHECKPOINT10_IMAGE_FILE)
    ) board (
        .core_clk(core_clk), .mig_clk(ui_clk), .rst_n(core_pll_locked),
        .mig_calib_complete(init_calib_complete && !ui_clk_sync_rst),
        .uart_rx(UART_TXD_IN), .dump_button(BTNC), .uart_tx(UART_RXD_OUT), .led(LED),
        .mig_req(mig_req), .mig_rsp(mig_rsp), .last_pc(last_pc), .last_cause(last_cause), .last_tval(last_tval)
    );

    // The fabric admits only 0x8000_0000..0x87ff_ffff DDR transactions.
    // Those physical addresses become 0..0x07ff_ffff on MIG's 27-bit port.
`ifndef SYNTHESIS
    always @(posedge ui_clk) if (mig_axi_resetn) begin
        if (mig_req.awvalid && mig_req.awaddr[31:27] != 5'b10000)
            $fatal(1, "MIG write address outside DDR window");
        if (mig_req.arvalid && mig_req.araddr[31:27] != 5'b10000)
            $fatal(1, "MIG read address outside DDR window");
    end
`endif

    ddr_probe_wrapper mig (
        .ddr2_sdram_addr(ddr2_addr), .ddr2_sdram_ba(ddr2_ba),
        .ddr2_sdram_cas_n(ddr2_cas_n), .ddr2_sdram_ck_n(ddr2_ck_n),
        .ddr2_sdram_ck_p(ddr2_ck_p), .ddr2_sdram_cke(ddr2_cke),
        .ddr2_sdram_ras_n(ddr2_ras_n), .ddr2_sdram_we_n(ddr2_we_n),
        .ddr2_sdram_dq(ddr2_dq), .ddr2_sdram_dqs_n(ddr2_dqs_n),
        .ddr2_sdram_dqs_p(ddr2_dqs_p), .ddr2_sdram_cs_n(ddr2_cs_n),
        .ddr2_sdram_dm(ddr2_dm), .ddr2_sdram_odt(ddr2_odt),
        .init_calib_complete(init_calib_complete),
        .ui_clk(ui_clk), .ui_clk_sync_rst(ui_clk_sync_rst),
        .aresetn(mig_axi_resetn),
        .S_AXI_awid(mig_req.awid), .S_AXI_awaddr(mig_req.awaddr[26:0]),
        .S_AXI_awlen({4'b0, mig_req.awlen}), .S_AXI_awsize(mig_req.awsize),
        .S_AXI_awburst(2'b01), .S_AXI_awlock(1'b0),
        .S_AXI_awcache(4'b0011), .S_AXI_awprot(3'b000), .S_AXI_awqos(4'b0000),
        .S_AXI_awvalid(mig_req.awvalid), .S_AXI_awready(mig_rsp.awready),
        .S_AXI_wdata(mig_req.wdata), .S_AXI_wstrb(mig_req.wstrb),
        .S_AXI_wlast(mig_req.wlast), .S_AXI_wvalid(mig_req.wvalid),
        .S_AXI_wready(mig_rsp.wready), .S_AXI_bid(mig_rsp.bid),
        .S_AXI_bresp(mig_rsp.bresp), .S_AXI_bvalid(mig_rsp.bvalid),
        .S_AXI_bready(mig_req.bready), .S_AXI_arid(mig_req.arid),
        .S_AXI_araddr(mig_req.araddr[26:0]),
        .S_AXI_arlen({4'b0, mig_req.arlen}), .S_AXI_arsize(mig_req.arsize),
        .S_AXI_arburst(2'b01), .S_AXI_arlock(1'b0),
        .S_AXI_arcache(4'b0011), .S_AXI_arprot(3'b000), .S_AXI_arqos(4'b0000),
        .S_AXI_arvalid(mig_req.arvalid), .S_AXI_arready(mig_rsp.arready),
        .S_AXI_rid(mig_rsp.rid), .S_AXI_rdata(mig_rsp.rdata),
        .S_AXI_rresp(mig_rsp.rresp), .S_AXI_rlast(mig_rsp.rlast),
        .S_AXI_rvalid(mig_rsp.rvalid), .S_AXI_rready(mig_req.rready),
        .sys_clk_i(sys_clk_i), .clk_ref_i(ref_clk_200), .sys_rst(CPU_RESETN)
    );
endmodule
