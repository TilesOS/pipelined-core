`timescale 1ns/1ps
// Testable board subsystem; only the outer pin wrapper depends on Vivado IP.
module checkpoint9_board_system #(
    parameter ROM_FILE = "checkpoint9_smoke.mem",
    parameter integer UART_CLOCKS_PER_BIT = 434,
    parameter integer REPORT_REPEAT_CYCLES = 50_000_000
) (
    input logic core_clk, mig_clk, rst_n, mig_calib_complete,
    output axi128_pkg::axi_req_t mig_req,
    input axi128_pkg::axi_rsp_t mig_rsp,
    output logic uart_tx, masters_ready, cpu_done, passed,
    output logic [31:0] phase, result
);
    import axi128_pkg::*;
    axi_req_t peripheral_req, dma_req;
    axi_rsp_t peripheral_rsp, dma_rsp;
    logic retire_valid, retire_trap;
    logic [31:0] retire_pc, retire_cause, retire_tval, last_pc, cause, tval;
    logic [31:0] imiss, dmiss, dwb, ibypass, dbypass, dma_trips, dma_errors, cycles;
    (* async_reg = "true" *) logic [1:0] calib_sync;
    logic [31:0] flags;
    assign passed = cpu_done && result == 32'hc900_600d && phase == 8 &&
                    cause == 3 && dma_errors == 0 && dma_trips != 0;
    assign flags = {28'b0, passed, cpu_done, masters_ready, calib_sync[1]};
    always_ff @(posedge core_clk or negedge rst_n) begin
        if (!rst_n) calib_sync <= 0;
        else calib_sync <= {calib_sync[0], mig_calib_complete};
    end
    always_ff @(posedge core_clk) begin
        if (!masters_ready) begin last_pc <= 0; cause <= 0; tval <= 0; cycles <= 0; end
        else begin
            if (!cpu_done) cycles <= cycles + 1;
            if (retire_valid) begin
                last_pc <= retire_pc;
                if (retire_trap) begin cause <= retire_cause; tval <= retire_tval; end
            end
        end
    end
    checkpoint9_top cpu_system (
        .core_clk(core_clk), .mig_clk(mig_clk), .rst_n(rst_n),
        .mig_calib_complete(mig_calib_complete), .cpu_run(1'b1),
        .manual_halt(1'b0), .dump_button(1'b0), .masters_ready(masters_ready),
        .uart_tx(), .atomic_lock(), .loader_req('0), .loader_rsp(),
        .dma_req(dma_req), .dma_rsp(dma_rsp), .peripheral_req(peripheral_req),
        .peripheral_rsp(peripheral_rsp), .mig_req(mig_req), .mig_rsp(mig_rsp),
        .retire_valid(retire_valid), .retire_pc(retire_pc), .retire_insn(),
        .retire_rd(), .retire_rd_data(), .retire_mem_addr(), .retire_mem_wdata(),
        .retire_mem_rmask(), .retire_mem_wmask(), .retire_trap(retire_trap),
        .retire_cause(retire_cause), .retire_tval(retire_tval), .retire_csr_write(),
        .retire_csr_addr(), .retire_csr_data(), .done(cpu_done),
        .icache_misses(imiss), .dcache_misses(dmiss), .dcache_writebacks(dwb),
        .icache_bypasses(ibypass), .dcache_bypasses(dbypass)
    );
    checkpoint9_smoke_mmio #(.ROM_FILE(ROM_FILE)) mmio (
        .clk(core_clk), .rst_n(masters_ready), .req(peripheral_req), .rsp(peripheral_rsp),
        .icache_misses(imiss), .dcache_misses(dmiss), .dcache_writebacks(dwb),
        .icache_bypasses(ibypass), .dcache_bypasses(dbypass),
        .dma_trips(dma_trips), .dma_errors(dma_errors), .phase(phase), .result(result)
    );
    checkpoint9_smoke_dma traffic (
        .clk(core_clk), .rst_n(masters_ready), .stop(cpu_done),
        .req(dma_req), .rsp(dma_rsp), .trips(dma_trips), .errors(dma_errors)
    );
    checkpoint9_uart_report #(.CLOCKS_PER_BIT(UART_CLOCKS_PER_BIT),
        .REPEAT_CYCLES(REPORT_REPEAT_CYCLES)) report (
        .clk(core_clk), .rst_n(rst_n), .flags(flags), .phase(phase), .result(result),
        .last_pc(last_pc), .cause(cause), .tval(tval), .icache_misses(imiss),
        .dcache_misses(dmiss), .dcache_writebacks(dwb), .icache_bypasses(ibypass),
        .dcache_bypasses(dbypass), .dma_trips(dma_trips), .dma_errors(dma_errors),
        .cycles(cycles), .tx(uart_tx)
    );
endmodule
