`timescale 1ns/1ps
// Board execution boundary also used by the full loader/CPU simulation gate.
module checkpoint10_board_system #(
    parameter integer IMAGE_WORDS = 1,
    parameter IMAGE_FILE = "checkpoint10_image.mem",
    parameter integer BUTTON_STABLE_CYCLES = 500_000
) (
    input logic core_clk, mig_clk, rst_n, mig_calib_complete,
    input logic uart_rx, dump_button,
    output logic uart_tx,
    output logic [3:0] led,
    output logic [31:0] last_pc, last_cause, last_tval,
    output axi128_pkg::axi_req_t mig_req,
    input axi128_pkg::axi_rsp_t mig_rsp
);
    axi128_pkg::axi_req_t loader_req;
    axi128_pkg::axi_rsp_t loader_rsp;
    logic masters_ready, image_complete, image_error, cpu_done;
    logic console_tx, console_idle, debug_tx, halt_cpu, trace_button;
    logic retire_valid, retire_trap;
    logic [31:0] retire_pc, retire_data, retire_cause, retire_tval;
    logic [4:0] retire_rd;
    logic payload_pass, payload_fail;
    assign led = {payload_pass, image_error || payload_fail || cpu_done, image_complete, masters_ready};
    always_ff @(posedge core_clk) begin
        if (!masters_ready) begin payload_pass <= 0; payload_fail <= 0; end
        else if (retire_valid && !retire_trap && retire_pc >= 32'h80040000 &&
                 retire_pc < 32'h80050000 && retire_rd == 31) begin
            if (retire_data == 32'h600d) payload_pass <= 1;
            if (retire_data == 32'hbad) payload_fail <= 1;
        end
    end
    always_ff @(posedge core_clk) begin
        if (!masters_ready) begin last_pc <= 0; last_cause <= 0; last_tval <= 0; end
        else if (retire_valid) begin
            last_pc <= retire_pc;
            if (retire_trap) begin last_cause <= retire_cause; last_tval <= retire_tval; end
        end
    end
    checkpoint10_image_loader #(.IMAGE_WORDS(IMAGE_WORDS), .IMAGE_FILE(IMAGE_FILE)) loader (
        .clk(core_clk), .rst_n(masters_ready), .req(loader_req), .rsp(loader_rsp),
        .complete(image_complete), .error(image_error), .progress()
    );
    checkpoint10_uart_owner #(.BUTTON_STABLE_CYCLES(BUTTON_STABLE_CYCLES)) uart_owner (
        .clk(core_clk), .rst_n(masters_ready), .button(dump_button),
        .console_tx(console_tx), .console_idle(console_idle), .debug_tx(debug_tx),
        .uart_tx(uart_tx), .halt_cpu(halt_cpu), .trace_button(trace_button), .debug_selected()
    );
    checkpoint10_top #(.RESET_PC(32'h80000000)) system (
        .core_clk(core_clk), .mig_clk(mig_clk), .rst_n(rst_n), .mig_calib_complete(mig_calib_complete),
        .cpu_run(image_complete && !image_error), .manual_halt(halt_cpu), .dump_button(trace_button),
        .uart_rx(uart_rx), .dma_irq(1'b0), .uart_tx(console_tx), .uart_tx_idle(console_idle), .debug_uart_tx(debug_tx),
        .masters_ready(masters_ready), .atomic_lock(),
        .loader_req(loader_req), .loader_rsp(loader_rsp), .dma_req('0), .dma_rsp(),
        .mig_req(mig_req), .mig_rsp(mig_rsp),
        .retire_valid(retire_valid), .retire_priv(), .retire_pc(retire_pc), .retire_insn(),
        .retire_rd(retire_rd), .retire_rd_data(retire_data), .retire_mem_addr(), .retire_mem_wdata(),
        .retire_mem_rmask(), .retire_mem_wmask(), .retire_trap(retire_trap), .retire_cause(retire_cause), .retire_tval(retire_tval),
        .retire_csr_write(), .retire_csr_addr(), .retire_csr_data(), .done(cpu_done),
        .icache_misses(), .dcache_misses(), .dcache_writebacks(), .icache_bypasses(), .dcache_bypasses()
    );
endmodule
