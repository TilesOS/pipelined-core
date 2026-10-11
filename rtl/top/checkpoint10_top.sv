`timescale 1ns/1ps
// Checkpoint 10 CPU + standard devices, retaining checkpoint 9's MIG boundary.
// Console and hardware trace have separate TX pins at this integration boundary.
module checkpoint10_top #(
    parameter logic [31:0] RESET_PC = 32'h0000_0000,
    parameter integer UART_CLOCKS_PER_BIT = 434
) (
    input logic core_clk, mig_clk, rst_n, mig_calib_complete,
    input logic cpu_run, manual_halt, dump_button,
    input logic uart_rx, dma_irq,
    output logic masters_ready, uart_tx, uart_tx_idle, debug_uart_tx, atomic_lock,
    input axi128_pkg::axi_req_t loader_req, dma_req,
    output axi128_pkg::axi_rsp_t loader_rsp, dma_rsp,
    output axi128_pkg::axi_req_t mig_req,
    input axi128_pkg::axi_rsp_t mig_rsp,
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
    axi128_pkg::axi_req_t peripheral_req;
    axi128_pkg::axi_rsp_t peripheral_rsp;
    logic msip_irq, mtip_irq, meip_irq, seip_irq;
    logic [63:0] time_value;
    checkpoint10_mmio mmio (
        .clk(core_clk), .rst_n(masters_ready), .uart_rx(uart_rx), .uart_tx(uart_tx), .uart_tx_idle(uart_tx_idle), .dma_irq(dma_irq),
        .msip_irq(msip_irq), .mtip_irq(mtip_irq), .meip_irq(meip_irq), .seip_irq(seip_irq), .time_value(time_value),
        .axi_req(peripheral_req), .axi_rsp(peripheral_rsp)
    );
    checkpoint9_top #(.ENABLE_PRIVILEGE(1), .RESET_PC(RESET_PC), .UART_CLOCKS_PER_BIT(UART_CLOCKS_PER_BIT)) system (
        .core_clk(core_clk), .mig_clk(mig_clk), .rst_n(rst_n), .mig_calib_complete(mig_calib_complete),
        .cpu_run(cpu_run), .manual_halt(manual_halt), .dump_button(dump_button),
        .msip_irq(msip_irq), .mtip_irq(mtip_irq), .meip_irq(meip_irq), .seip_irq(seip_irq), .time_value(time_value),
        .masters_ready(masters_ready), .uart_tx(debug_uart_tx), .atomic_lock(atomic_lock),
        .loader_req(loader_req), .loader_rsp(loader_rsp), .dma_req(dma_req), .dma_rsp(dma_rsp),
        .peripheral_req(peripheral_req), .peripheral_rsp(peripheral_rsp), .mig_req(mig_req), .mig_rsp(mig_rsp),
        .retire_valid(retire_valid),
        .retire_priv(retire_priv),
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
endmodule
