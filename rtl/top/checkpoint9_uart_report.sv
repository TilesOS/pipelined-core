`timescale 1ns/1ps
// Snapshot then repeat C9SM v1: header + fourteen little-endian 32-bit words.
// Starts before calibration and remains independent of CPU/cache progress.
module checkpoint9_uart_report #(
    parameter integer CLOCKS_PER_BIT = 434,
    parameter integer REPEAT_CYCLES = 50_000_000
) (
    input logic clk, rst_n,
    input logic [31:0] flags, phase, result, last_pc, cause, tval,
    input logic [31:0] icache_misses, dcache_misses, dcache_writebacks,
    input logic [31:0] icache_bypasses, dcache_bypasses, dma_trips, dma_errors, cycles,
    output logic tx
);
    logic sending, tx_ready, tx_valid;
    logic [5:0] byte_index;
    logic [31:0] pause_count;
    logic [31:0] snapshot [14];
    logic [7:0] tx_data;
    always_comb begin
        tx_data = 0;
        case (byte_index)
            0: tx_data = "C";
            1: tx_data = "9";
            2: tx_data = "S";
            3: tx_data = "M";
            4: tx_data = 1;
            default: if (byte_index <= 60)
                tx_data = 8'(snapshot[4'((byte_index-6'd5) >> 2)] >>
                             (8*((byte_index-6'd5) & 6'd3)));
        endcase
        tx_valid = sending && tx_ready;
    end
    uart_tx_byte #(.CLOCKS_PER_BIT(CLOCKS_PER_BIT)) uart (
        .clk(clk), .rst_n(rst_n), .valid(tx_valid), .data(tx_data), .ready(tx_ready), .tx(tx)
    );
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            sending <= 0; byte_index <= 0; pause_count <= 0;
            for (int i = 0; i < 14; i++) snapshot[i] <= 0;
        end else if (!sending) begin
            if (pause_count == 0) begin
                snapshot[0] <= flags; snapshot[1] <= phase; snapshot[2] <= result;
                snapshot[3] <= last_pc; snapshot[4] <= cause; snapshot[5] <= tval;
                snapshot[6] <= icache_misses; snapshot[7] <= dcache_misses;
                snapshot[8] <= dcache_writebacks; snapshot[9] <= icache_bypasses;
                snapshot[10] <= dcache_bypasses; snapshot[11] <= dma_trips;
                snapshot[12] <= dma_errors; snapshot[13] <= cycles;
                byte_index <= 0; sending <= 1;
            end else pause_count <= pause_count - 1;
        end else if (tx_valid) begin
            if (byte_index == 60) begin
                sending <= 0; pause_count <= REPEAT_CYCLES;
            end else byte_index <= byte_index + 1'b1;
        end
    end
endmodule
