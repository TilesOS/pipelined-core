`timescale 1ns/1ps
module checkpoint10_uart_owner_tb;
    logic clk = 0, rst_n = 0, button = 0, console_tx = 1, console_idle = 0, debug_tx = 1;
    logic uart_tx, halt_cpu, trace_button, debug_selected;
    always #5 clk = !clk;
    checkpoint10_uart_owner #(.BUTTON_STABLE_CYCLES(3), .QUIET_CYCLES(4)) dut (.*);
    initial begin
        repeat (5) @(negedge clk);
        rst_n = 1;
        button = 1;
        // A high physical TX is insufficient: FIFO/serializer must be empty.
        repeat (20) @(negedge clk);
        if (!halt_cpu || debug_selected || trace_button) $fatal(1, "early UART ownership");
        console_idle = 1;
        repeat (2) @(negedge clk);
        console_idle = 0;
        repeat (5) @(negedge clk);
        if (debug_selected) $fatal(1, "quiet window did not restart");
        console_idle = 1;
        repeat (10) @(negedge clk);
        if (!debug_selected || !trace_button || !halt_cpu) $fatal(1, "trace did not acquire UART");
        debug_tx = 0;
        @(negedge clk);
        if (uart_tx) $fatal(1, "debug start bit lost");
        button = 0; console_idle = 0; console_tx = 0; debug_tx = 1;
        repeat (10) @(negedge clk);
        if (!uart_tx || !debug_selected || !halt_cpu) $fatal(1, "trace tail/ownership lost");
        rst_n = 0;
        repeat (5) @(negedge clk);
        if (uart_tx || halt_cpu || debug_selected || trace_button) $fatal(1, "ownership reset failed");
        $display("PASS: UART owner debounces, halts, waits for FIFO/serializer drain and preserves trace tail until reset");
        $finish;
    end
endmodule
