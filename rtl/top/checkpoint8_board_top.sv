`timescale 1ns/1ps
// Checkpoint 8 board-only DDR2 measurement shell. The MIG instance matches
// the generated ddr_probe_mig_7series_0_0 template from Vivado 2026.1.
module checkpoint8_board_top (
    input  wire        sys_clk_i,
    input  wire        CPU_RESETN,
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
    wire ui_clk, ui_clk_sync_rst, mig_mmcm_locked;
    wire init_calib_complete;
    wire masters_ready;
    wire benchmark_done;
    wire mig_axi_resetn;
    logic [25:0] heartbeat;
    logic [31:0] baseline_write_cycles, baseline_read_cycles;
    logic [31:0] contended_write_cycles, contended_read_cycles;
    logic [31:0] dma_errors, cpu_errors, cpu_round_trips;
    axi_req_t dma_req, cpu_req, peripheral_req, mig_req;
    axi_rsp_t dma_rsp, cpu_rsp, peripheral_rsp, mig_rsp;
    axi_req4_t master_req;
    axi_rsp4_t master_rsp;
    logic [1:0] read_owner, write_owner, active;
    logic [2:0] aw_level, w_level, ar_level, b_level, r_level;

    checkpoint8_core_clock clocks (
        .clk100(sys_clk_i), .rst_n(CPU_RESETN), .clk50(core_clk),
        .clk200(ref_clk_200), .locked(core_pll_locked)
    );
    assign mig_axi_resetn = CPU_RESETN && !ui_clk_sync_rst;
    always_ff @(posedge core_clk or negedge CPU_RESETN) begin
        if (!CPU_RESETN) heartbeat <= 0;
        else heartbeat <= heartbeat + 1'b1;
    end
    assign LED[0] = init_calib_complete;
    assign LED[1] = benchmark_done;
    assign LED[2] = (dma_errors != 0 || cpu_errors != 0);
    assign LED[3] = heartbeat[25];

    always_comb begin
        master_req = '0;
        master_req[0] = dma_req;
        master_req[1] = cpu_req;
        dma_rsp = master_rsp[0];
        cpu_rsp = master_rsp[1];
        peripheral_rsp = '0;
    end
    checkpoint8_traffic traffic (
        .clk(core_clk), .rst_n(masters_ready), .run(masters_ready),
        .dma_req(dma_req), .dma_rsp(dma_rsp),
        .cpu_req(cpu_req), .cpu_rsp(cpu_rsp), .done(benchmark_done),
        .baseline_write_cycles(baseline_write_cycles),
        .baseline_read_cycles(baseline_read_cycles),
        .contended_write_cycles(contended_write_cycles),
        .contended_read_cycles(contended_read_cycles),
        .dma_errors(dma_errors), .cpu_errors(cpu_errors),
        .cpu_round_trips(cpu_round_trips)
    );
    checkpoint8_uart_report report (
        .clk(core_clk), .rst_n(masters_ready), .done(benchmark_done),
        .baseline_write_cycles(baseline_write_cycles),
        .baseline_read_cycles(baseline_read_cycles),
        .contended_write_cycles(contended_write_cycles),
        .contended_read_cycles(contended_read_cycles),
        .dma_errors(dma_errors), .cpu_errors(cpu_errors),
        .cpu_round_trips(cpu_round_trips), .tx(UART_RXD_OUT)
    );
    axi_subsystem subsystem (
        .core_clk(core_clk), .mig_clk(ui_clk),
        .rst_n(CPU_RESETN && core_pll_locked && !ui_clk_sync_rst),
        .mig_calib_complete(init_calib_complete), .masters_ready(masters_ready),
        .master_req(master_req), .master_rsp(master_rsp),
        .peripheral_req(peripheral_req), .peripheral_rsp(peripheral_rsp),
        .mig_req(mig_req), .mig_rsp(mig_rsp),
        .read_owner_probe(read_owner), .write_owner_probe(write_owner),
        .active_probe(active), .aw_level(aw_level), .w_level(w_level),
        .ar_level(ar_level), .b_level(b_level), .r_level(r_level)
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

    ddr_probe_mig_7series_0_0 mig (
        .ddr2_addr(ddr2_addr), .ddr2_ba(ddr2_ba), .ddr2_cas_n(ddr2_cas_n),
        .ddr2_ck_n(ddr2_ck_n), .ddr2_ck_p(ddr2_ck_p), .ddr2_cke(ddr2_cke),
        .ddr2_ras_n(ddr2_ras_n), .ddr2_we_n(ddr2_we_n), .ddr2_dq(ddr2_dq),
        .ddr2_dqs_n(ddr2_dqs_n), .ddr2_dqs_p(ddr2_dqs_p),
        .ddr2_cs_n(ddr2_cs_n), .ddr2_dm(ddr2_dm), .ddr2_odt(ddr2_odt),
        .init_calib_complete(init_calib_complete),
        .ui_clk(ui_clk), .ui_clk_sync_rst(ui_clk_sync_rst),
        .ui_addn_clk_0(), .ui_addn_clk_1(), .ui_addn_clk_2(),
        .ui_addn_clk_3(), .ui_addn_clk_4(), .mmcm_locked(mig_mmcm_locked),
        .aresetn(mig_axi_resetn), .app_sr_active(), .app_ref_ack(), .app_zq_ack(),
        .s_axi_awid(mig_req.awid), .s_axi_awaddr(mig_req.awaddr[26:0]),
        .s_axi_awlen({4'b0, mig_req.awlen}), .s_axi_awsize(mig_req.awsize),
        .s_axi_awburst(2'b01), .s_axi_awlock(1'b0),
        .s_axi_awcache(4'b0011), .s_axi_awprot(3'b000), .s_axi_awqos(4'b0000),
        .s_axi_awvalid(mig_req.awvalid), .s_axi_awready(mig_rsp.awready),
        .s_axi_wdata(mig_req.wdata), .s_axi_wstrb(mig_req.wstrb),
        .s_axi_wlast(mig_req.wlast), .s_axi_wvalid(mig_req.wvalid),
        .s_axi_wready(mig_rsp.wready), .s_axi_bid(mig_rsp.bid),
        .s_axi_bresp(mig_rsp.bresp), .s_axi_bvalid(mig_rsp.bvalid),
        .s_axi_bready(mig_req.bready), .s_axi_arid(mig_req.arid),
        .s_axi_araddr(mig_req.araddr[26:0]),
        .s_axi_arlen({4'b0, mig_req.arlen}), .s_axi_arsize(mig_req.arsize),
        .s_axi_arburst(2'b01), .s_axi_arlock(1'b0),
        .s_axi_arcache(4'b0011), .s_axi_arprot(3'b000), .s_axi_arqos(4'b0000),
        .s_axi_arvalid(mig_req.arvalid), .s_axi_arready(mig_rsp.arready),
        .s_axi_rid(mig_rsp.rid), .s_axi_rdata(mig_rsp.rdata),
        .s_axi_rresp(mig_rsp.rresp), .s_axi_rlast(mig_rsp.rlast),
        .s_axi_rvalid(mig_rsp.rvalid), .s_axi_rready(mig_req.rready),
        .sys_clk_i(sys_clk_i), .clk_ref_i(ref_clk_200), .sys_rst(CPU_RESETN)
    );
endmodule
