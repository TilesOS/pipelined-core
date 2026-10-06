`timescale 1ns/1ps
// Synthesizable CPU/cache/fabric/CDC boundary for the board's MIG AXI ports.
// DMA is noncoherent: external masters may access cached DDR only while the
// CPU is held reset. During execution, DMA uses the uncached pool exclusively.
module checkpoint9_top #(
    parameter bit ENABLE_PRIVILEGE = 0,
    parameter logic [31:0] RESET_PC = 32'h0000_0000,
    parameter integer UART_CLOCKS_PER_BIT = 434
) (
    input logic core_clk, mig_clk, rst_n, mig_calib_complete,
    input logic cpu_run, manual_halt, dump_button,
    input logic msip_irq, mtip_irq, meip_irq, seip_irq,
    input logic [63:0] time_value,
    output logic masters_ready, uart_tx, atomic_lock,
    input axi128_pkg::axi_req_t loader_req, dma_req,
    output axi128_pkg::axi_rsp_t loader_rsp, dma_rsp,
    output axi128_pkg::axi_req_t peripheral_req, mig_req,
    input axi128_pkg::axi_rsp_t peripheral_rsp, mig_rsp,
    output logic retire_valid,
    output logic [1:0] retire_priv,
    output logic [31:0] retire_pc, retire_insn,
    output logic [4:0] retire_rd,
    output logic [31:0] retire_rd_data, retire_mem_addr, retire_mem_wdata,
    output logic [3:0] retire_mem_rmask, retire_mem_wmask,
    output logic retire_trap,
    output logic [31:0] retire_cause, retire_tval,
    output logic retire_csr_write,
    output logic [11:0] retire_csr_addr,
    output logic [31:0] retire_csr_data,
    output logic done,
    output logic [31:0] icache_misses, dcache_misses, dcache_writebacks,
    output logic [31:0] icache_bypasses, dcache_bypasses
);
    import axi128_pkg::*;
    axi_req4_t req;
    axi_rsp4_t rsp;
    logic [1:0] active;
    logic external_store;
    logic [31:0] external_addr;
    logic [3:0] external_word_mask;
    logic [31:0] external_write_addr [2];
    // Prevent new competing writes during an atomic interval. Drain already
    // granted transactions before the CPU starts the atomic read. W and B
    // remain connected so an older transaction cannot deadlock the lock.
    always_comb begin
        req[2] = loader_req; req[3] = dma_req;
        req[2].awvalid = loader_req.awvalid && !atomic_lock;
        req[3].awvalid = dma_req.awvalid && !atomic_lock;
        loader_rsp = rsp[2]; dma_rsp = rsp[3];
        loader_rsp.awready = rsp[2].awready && !atomic_lock;
        dma_rsp.awready = rsp[3].awready && !atomic_lock;
    end
    // Snoop every accepted strobed W beat, including later burst beats.
    // A sparse write to another word preserves LR. Clearing at W admission
    // is conservative; the atomic drain barrier still waits for the final B.
    assign external_store = (req[2].wvalid && rsp[2].wready) || (req[3].wvalid && rsp[3].wready);
    assign external_addr = rsp[2].wready ? external_write_addr[0] : external_write_addr[1];
    always_comb begin
        for (int word_lane = 0; word_lane < 4; word_lane++)
            external_word_mask[word_lane] = rsp[2].wready ?
                |req[2].wstrb[4*word_lane +: 4] : |req[3].wstrb[4*word_lane +: 4];
    end
    always_ff @(posedge core_clk) begin
        if (!masters_ready) begin external_write_addr[0] <= 0; external_write_addr[1] <= 0; end
        else begin
            if (req[2].awvalid && rsp[2].awready) external_write_addr[0] <= req[2].awaddr;
            if (req[3].awvalid && rsp[3].awready) external_write_addr[1] <= req[3].awaddr;
            if (req[2].wvalid && rsp[2].wready) external_write_addr[0] <= external_write_addr[0] + 16;
            if (req[3].wvalid && rsp[3].wready) external_write_addr[1] <= external_write_addr[1] + 16;
        end
    end
    rv32_cached_core #(.ENABLE_PRIVILEGE(ENABLE_PRIVILEGE), .RESET_PC(RESET_PC), .UART_CLOCKS_PER_BIT(UART_CLOCKS_PER_BIT)) cpu (
        .clk(core_clk), .rst_n(masters_ready && cpu_run), .manual_halt(manual_halt), .dump_button(dump_button),
        .msip_irq(msip_irq), .mtip_irq(mtip_irq), .meip_irq(meip_irq), .seip_irq(seip_irq), .time_value(time_value),
        .external_store_valid(external_store), .external_store_addr(external_addr),
        .external_store_word_mask(external_word_mask),
        .allow_atomic_read(!active[1]), .atomic_lock(atomic_lock),
        .instruction_req(req[0]), .instruction_rsp(rsp[0]), .data_req(req[1]), .data_rsp(rsp[1]),
        .uart_tx(uart_tx), .dump_busy(), .trace_count(), .trace_write_ptr(), .ila_pipeline(),
        .retire_valid(retire_valid), .retire_pc(retire_pc), .retire_insn(retire_insn), .retire_priv(retire_priv),
        .retire_rd(retire_rd), .retire_rd_data(retire_rd_data), .retire_mem_addr(retire_mem_addr),
        .retire_mem_rmask(retire_mem_rmask), .retire_mem_wmask(retire_mem_wmask),
        .retire_mem_wdata(retire_mem_wdata), .retire_trap(retire_trap),
        .retire_cause(retire_cause), .retire_tval(retire_tval), .retire_csr_write(retire_csr_write),
        .retire_csr_addr(retire_csr_addr), .retire_csr_data(retire_csr_data), .done(done),
        .icache_misses(icache_misses), .dcache_misses(dcache_misses), .dcache_writebacks(dcache_writebacks),
        .icache_bypasses(icache_bypasses), .dcache_bypasses(dcache_bypasses)
    );
    axi_subsystem #(.DMA_UNCACHED_ONLY(1)) bus (
        .core_clk(core_clk), .mig_clk(mig_clk), .rst_n(rst_n), .mig_calib_complete(mig_calib_complete),
        .masters_ready(masters_ready), .master_req(req), .master_rsp(rsp),
        .peripheral_req(peripheral_req), .peripheral_rsp(peripheral_rsp), .mig_req(mig_req), .mig_rsp(mig_rsp),
        .read_owner_probe(), .write_owner_probe(), .active_probe(active),
        .aw_level(), .w_level(), .ar_level(), .b_level(), .r_level()
    );
endmodule
