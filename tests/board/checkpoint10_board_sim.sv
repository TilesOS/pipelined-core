`timescale 1ns/1ps
`include "checkpoint10_image.svh"
module checkpoint10_board_sim (
    input logic core_clk, mig_clk, rst_n, calibrated, uart_rx, dump_button,
    output logic uart_tx,
    output logic [31:0] last_pc, last_cause, last_tval,
    output logic [3:0] led
);
    axi128_pkg::axi_req_t req;
    axi128_pkg::axi_rsp_t rsp;
    checkpoint10_board_system #(
        .IMAGE_WORDS(`CHECKPOINT10_IMAGE_WORDS), .IMAGE_FILE(`CHECKPOINT10_IMAGE_FILE),
        .BUTTON_STABLE_CYCLES(3)
    ) board (
        .core_clk(core_clk), .mig_clk(mig_clk), .rst_n(rst_n), .mig_calib_complete(calibrated),
        .uart_rx(uart_rx), .dump_button(dump_button), .uart_tx(uart_tx), .led(led),
        .mig_req(req), .mig_rsp(rsp), .last_pc(last_pc), .last_cause(last_cause), .last_tval(last_tval)
    );
    // Deliberately start with nonzero DDR; only the hardware loader supplies
    // firmware. LFSR admission/response backpressure is unrelated to the CPU.
    cache_test_memory #(.BYTES(1048576), .LINEAR_DDR(1)) memory (
        .clk(mig_clk), .rst_n(rst_n), .req(req), .rsp(rsp)
    );
endmodule
