`timescale 1ns/1ps
module privileged_core_sim (
    input logic clk, mig_clk, rst_n, mig_calib_complete,
    input logic manual_halt, dump_button,
    output logic uart_tx, atomic_lock, masters_ready,
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
    axi_req_t mig_req;
    axi_rsp_t mig_rsp;
    checkpoint10_top #(.RESET_PC(32'h8000_0000), .UART_CLOCKS_PER_BIT(8)) system (
        .core_clk(clk), .mig_clk(mig_clk), .rst_n(rst_n), .mig_calib_complete(mig_calib_complete),
        .cpu_run(1'b1), .manual_halt(manual_halt), .dump_button(dump_button), .uart_rx(1'b1), .dma_irq(1'b0), .debug_uart_tx(), .uart_tx(uart_tx),
        .masters_ready(masters_ready), .atomic_lock(atomic_lock),
        .loader_req('0), .loader_rsp(), .dma_req('0), .dma_rsp(),
        .mig_req(mig_req), .mig_rsp(mig_rsp),
        .retire_priv(retire_priv), .retire_valid(retire_valid),
        .retire_pc(retire_pc),
        .retire_insn(retire_insn),
        .retire_rd(retire_rd),
        .retire_rd_data(retire_rd_data),
        .retire_mem_addr(retire_mem_addr),
        .retire_mem_wdata(retire_mem_wdata),
        .retire_mem_rmask(retire_mem_rmask),
        .retire_mem_wmask(retire_mem_wmask),
        .retire_trap(retire_trap),
        .retire_cause(retire_cause),
        .retire_tval(retire_tval),
        .retire_csr_write(retire_csr_write),
        .retire_csr_addr(retire_csr_addr),
        .retire_csr_data(retire_csr_data),
        .done(done),
        .icache_misses(icache_misses),
        .dcache_misses(dcache_misses),
        .dcache_writebacks(dcache_writebacks),
        .icache_bypasses(icache_bypasses),
        .dcache_bypasses(dcache_bypasses)
    );
    cache_test_memory #(.LOAD_IMAGE(1), .BYTES(1048576), .LINEAR_DDR(1)) memory (
        .clk(mig_clk), .rst_n(rst_n), .req(mig_req), .rsp(mig_rsp)
    );
endmodule
