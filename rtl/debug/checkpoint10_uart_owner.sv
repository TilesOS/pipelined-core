`timescale 1ns/1ps
// One-way console -> diagnostic UART ownership until reset. Halt first, wait
// for the console FIFO AND serializer to drain, then launch the trace packet.
// Ownership remains with trace through its final stop bit, even after its
// packet FSM goes idle. The trace clock/reset never depends on CPU progress.
module checkpoint10_uart_owner #(
    parameter integer BUTTON_STABLE_CYCLES = 500_000,
    parameter integer QUIET_CYCLES = 64
) (
    input logic clk, rst_n, button,
    input logic console_tx, console_idle, debug_tx,
    output logic uart_tx, halt_cpu, trace_button, debug_selected
);
    (* async_reg = "true" *) logic button_meta, button_sync;
    logic [$clog2(BUTTON_STABLE_CYCLES+1)-1:0] debounce;
    logic [$clog2(QUIET_CYCLES+1)-1:0] quiet;
    assign uart_tx = debug_selected ? debug_tx : console_tx;
    // Keep the trace button asserted. Its own edge detector produces one dump.
    assign trace_button = debug_selected;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin button_meta <= 0; button_sync <= 0; end
        else begin button_meta <= button; button_sync <= button_meta; end
    end
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            debounce <= 0; quiet <= 0; halt_cpu <= 0; debug_selected <= 0;
        end else begin
            if (!button_sync) debounce <= 0;
            else if (debounce != $bits(debounce)'(BUTTON_STABLE_CYCLES)) debounce <= debounce + 1'b1;
            if (debounce == $bits(debounce)'(BUTTON_STABLE_CYCLES)) halt_cpu <= 1;
            if (!halt_cpu || !console_idle) quiet <= 0;
            else if (quiet != $bits(quiet)'(QUIET_CYCLES)) quiet <= quiet + 1'b1;
            if (halt_cpu && console_idle && quiet == $bits(quiet)'(QUIET_CYCLES)) debug_selected <= 1;
        end
    end
endmodule
