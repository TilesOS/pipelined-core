timeunit 1ns;
timeprecision 1ps;
module uart16550_tb;
    logic clk = 0, rst_n = 0, uart_rx = 1, uart_tx, irq;
    always #5 clk = ~clk;
    logic req_valid = 0, req_ready, req_write = 0, rsp_valid, rsp_error, rsp_ready = 0;
    logic [31:0] req_addr = 0, req_wdata = 0, rsp_rdata;
    logic [1:0] req_size = 0;
    logic [3:0] req_wstrb = 1;
    uart16550 #(.DEFAULT_DIVISOR(1)) dut (
        .clk(clk), .rst_n(rst_n), .uart_rx(uart_rx), .uart_tx(uart_tx), .uart_tx_idle(), .irq(irq),
        .bus_req_valid(req_valid), .bus_req_ready(req_ready), .bus_req_write(req_write),
        .bus_req_addr(req_addr), .bus_req_size(req_size), .bus_req_wdata(req_wdata), .bus_req_wstrb(req_wstrb),
        .bus_rsp_valid(rsp_valid), .bus_rsp_ready(rsp_ready), .bus_rsp_rdata(rsp_rdata), .bus_rsp_error(rsp_error)
    );
    initial begin #2000000; $fatal(1, "UART watchdog"); end
    task automatic access(input bit w, input int offset, input logic [7:0] data,
                          input logic [7:0] expected, input bit check_data = 1,
                          input bit error_expected = 0);
        @(negedge clk);
        req_valid = 1; req_write = w; req_addr = 32'h1000_0000 + 32'(offset); req_wdata = {24'b0, data};
        do @(posedge clk); while (!req_ready);
        @(negedge clk); req_valid = 0;
        if (!rsp_valid || rsp_error != error_expected || (check_data && !w && rsp_rdata != {24'b0, expected}))
            $fatal(1, "UART offset=%0d got=%h expected=%h error=%b", offset, rsp_rdata, expected, rsp_error);
        repeat (3) begin
            @(posedge clk);
            if (!rsp_valid || rsp_error != error_expected || (check_data && !w && rsp_rdata != {24'b0, expected}))
                $fatal(1, "UART response changed while held");
        end
        @(negedge clk); rsp_ready = 1;
        @(negedge clk); rsp_ready = 0;
    endtask
    task automatic send_byte(input logic [7:0] data, input bit parity_enable = 0,
                             input bit bad_parity = 0, input bit bad_stop = 0);
        @(negedge clk); uart_rx = 0;
        repeat (16) @(negedge clk);
        for (int i = 0; i < 8; i++) begin
            uart_rx = data[i]; repeat (16) @(negedge clk);
        end
        if (parity_enable) begin uart_rx = (^data) ^ bad_parity; repeat (16) @(negedge clk); end
        uart_rx = !bad_stop; repeat (16) @(negedge clk);
        uart_rx = 1; repeat (8) @(negedge clk);
    endtask
    task automatic receive_tx(input logic [7:0] expected);
        logic [7:0] value;
        @(negedge uart_tx);
        repeat (24) @(negedge clk);
        for (int i = 0; i < 8; i++) begin value[i] = uart_tx; repeat (16) @(negedge clk); end
        if (value != expected || !uart_tx) $fatal(1, "UART serial TX value=%h", value);
    endtask
    initial begin
        repeat (4) @(negedge clk); rst_n = 1;
        access(0, 5, 0, 8'h60); access(0, 2, 0, 1);
        access(1, 3, 8'h83, 0); access(0, 0, 0, 1); access(0, 1, 0, 0);
        access(1, 0, 2, 0); access(0, 0, 0, 2); access(1, 0, 1, 0);
        access(1, 3, 3, 0); access(1, 7, 8'ha5, 0); access(0, 7, 0, 8'ha5);
        access(1, 1, 2, 0); if (!irq) $fatal(1, "THRE enable");
        access(0, 2, 0, 2); if (irq) $fatal(1, "IIR did not acknowledge THRE");
        fork
            receive_tx(8'ha6);
            access(1, 0, 8'ha6, 0);
        join
        wait (!dut.tx_busy); access(0, 5, 0, 8'h60);
        access(1, 1, 1, 0);
        send_byte(8'h59); if (!irq) $fatal(1, "RX interrupt");
        access(0, 2, 0, 4); access(0, 0, 0, 8'h59); if (irq) $fatal(1, "RBR pop");
        // FIFO trigger four, then character timeout below trigger.
        access(1, 2, 8'h47, 0);
        send_byte(1); send_byte(2); send_byte(3); send_byte(4);
        access(0, 2, 0, 8'hc4);
        access(0, 0, 0, 1); access(0, 0, 0, 2); access(0, 0, 0, 3);
        repeat (650) @(negedge clk); access(0, 2, 0, 8'hcc); access(0, 0, 0, 4);
        access(0, 2, 0, 8'hc1);
        // Error IRQ outranks RX; reading LSR clears head error and overrun.
        access(1, 3, 8'h1b, 0); access(1, 1, 5, 0);
        send_byte(8'h55, 1, 1); access(0, 2, 0, 8'hc6); access(0, 5, 0, 8'he5);
        access(0, 5, 0, 8'h61); access(0, 0, 0, 8'h55);
        access(1, 3, 3, 0); send_byte(0, 0, 0, 1);
        access(0, 5, 0, 8'hf9); access(0, 0, 0, 0);
        for (int i = 0; i < 17; i++) send_byte(8'(i));
        access(0, 5, 0, 8'h63);
        for (int i = 0; i < 16; i++) access(0, 0, 0, 8'(i));
        access(0, 5, 0, 8'h60);
        // Invalid accesses cannot pop data or update SCR.
        send_byte(8'h7a); req_size = 2; access(0, 0, 0, 0, 1, 1); req_size = 0;
        access(0, 0, 0, 8'h7a);
        req_wstrb = 2; access(1, 7, 0, 0, 0, 1); req_wstrb = 1;
        access(0, 7, 0, 8'ha5); access(0, 8, 0, 0, 1, 1);
        // Modem loopback and delta IRQ.
        access(1, 1, 8, 0); access(1, 4, 8'h10, 0);
        access(0, 2, 0, 8'hc0); access(0, 6, 0, 8'h0b); access(0, 6, 0, 0);
        access(1, 4, 8'h1f, 0); access(0, 6, 0, 8'hfb);
        // Internal serial loopback exercises TX FIFO ordering and RX.
        access(1, 1, 0, 0); access(1, 2, 7, 0);
        access(1, 0, 8'h12, 0); access(1, 0, 8'h34, 0); access(1, 0, 8'h56, 0);
        repeat (520) begin @(negedge clk); if (!uart_tx) $fatal(1, "loopback leaked external TX"); end
        access(0, 0, 0, 8'h12); access(0, 0, 0, 8'h34); access(0, 0, 0, 8'h56);
        access(1, 3, 8'h0c, 0); // five bits, odd parity, 1.5 stop
        access(1, 0, 8'hff, 0);
        wait (!dut.tx_busy && dut.tx_count == 0);
        repeat (20) @(negedge clk);
        access(0, 0, 0, 8'h1f); access(0, 5, 0, 8'h60);
        $display("PASS: UART divisor, serial TX/RX, FIFOs, timeout, IRQ priority/ack, parity/break/overrun, loopback and held responses");
        $finish;
    end
endmodule
