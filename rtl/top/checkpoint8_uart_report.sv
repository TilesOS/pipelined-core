`timescale 1ns/1ps
// Repeats a fixed 33-byte binary report at 115200 baud. The host can attach
// after the benchmark completes and still capture a full result.
module checkpoint8_uart_report #(
    parameter integer CLOCKS_PER_BIT = 434,
    parameter integer REPEAT_CYCLES = 50_000_000
) (
    input  logic clk,
    input  logic rst_n,
    input  logic done,
    input  logic [31:0] baseline_write_cycles,
    input  logic [31:0] baseline_read_cycles,
    input  logic [31:0] contended_write_cycles,
    input  logic [31:0] contended_read_cycles,
    input  logic [31:0] dma_errors,
    input  logic [31:0] cpu_errors,
    input  logic [31:0] cpu_round_trips,
    output logic tx
);
    typedef enum logic [1:0] {S_WAIT_DONE, S_SEND, S_PAUSE} state_t;
    state_t state;
    logic [5:0] byte_index;
    logic [31:0] pause_count;
    logic [31:0] selected_word;
    logic [7:0] tx_data;
    logic tx_valid, tx_ready;

    always_comb begin
        selected_word = 0;
        case ((byte_index - 6'd5) >> 2)
            0: selected_word = baseline_write_cycles;
            1: selected_word = baseline_read_cycles;
            2: selected_word = contended_write_cycles;
            3: selected_word = contended_read_cycles;
            4: selected_word = dma_errors;
            5: selected_word = cpu_errors;
            6: selected_word = cpu_round_trips;
            default: ;
        endcase
        case (byte_index)
            0: tx_data = "D";
            1: tx_data = "8";
            2: tx_data = "B";
            3: tx_data = "M";
            4: tx_data = 8'd1;
            default: tx_data = 8'(selected_word >> (8 * ((byte_index - 6'd5) & 6'd3)));
        endcase
        tx_valid = state == S_SEND && tx_ready;
    end

    uart_tx_byte #(.CLOCKS_PER_BIT(CLOCKS_PER_BIT)) uart (
        .clk(clk), .rst_n(rst_n), .valid(tx_valid), .data(tx_data),
        .ready(tx_ready), .tx(tx)
    );
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_WAIT_DONE;
            byte_index <= 0;
            pause_count <= 0;
        end else begin
            case (state)
                S_WAIT_DONE: if (done) begin
                    byte_index <= 0;
                    state <= S_SEND;
                end
                S_SEND: if (tx_valid) begin
                    if (byte_index == 6'd32) begin
                        pause_count <= 0;
                        state <= S_PAUSE;
                    end else byte_index <= byte_index + 1'b1;
                end
                S_PAUSE: if (pause_count == REPEAT_CYCLES-1) begin
                    byte_index <= 0;
                    state <= S_SEND;
                end else pause_count <= pause_count + 1;
                default: state <= S_WAIT_DONE;
            endcase
        end
    end
endmodule
