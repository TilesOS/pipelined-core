timeunit 1ns;
timeprecision 1ps;
module plic_tb;
    logic clk = 0;
    logic rst_n = 0;
    always #5 clk = ~clk;
    logic uart_irq, dma_irq, meip_irq, seip_irq;
    logic req_valid, req_ready, req_write, rsp_valid, rsp_ready, rsp_error;
    logic [31:0] req_addr, req_wdata, rsp_rdata;
    logic [1:0] req_size;
    logic [3:0] req_wstrb;
    int cycles = 0;

    plic dut (
        .clk(clk), .rst_n(rst_n), .uart_irq(uart_irq), .dma_irq(dma_irq),
        .bus_req_valid(req_valid), .bus_req_ready(req_ready),
        .bus_req_write(req_write), .bus_req_addr(req_addr),
        .bus_req_size(req_size), .bus_req_wdata(req_wdata),
        .bus_req_wstrb(req_wstrb), .bus_rsp_valid(rsp_valid),
        .bus_rsp_ready(rsp_ready), .bus_rsp_rdata(rsp_rdata),
        .bus_rsp_error(rsp_error), .meip_irq(meip_irq), .seip_irq(seip_irq)
    );
    always @(posedge clk) begin
        cycles++;
        if (cycles > 3000) $fatal(1, "PLIC watchdog");
    end

    task automatic access(input bit write_op, input logic [31:0] addr,
                          input logic [1:0] size, input logic [31:0] data,
                          input logic [3:0] strobes, input bit expect_error,
                          input logic [31:0] expect_data, input bit check_data);
        @(negedge clk);
        req_valid = 1;
        req_write = write_op;
        req_addr = addr;
        req_size = size;
        req_wdata = data;
        req_wstrb = strobes;
        do @(posedge clk); while (!req_ready);
        @(negedge clk);
        req_valid = 0;
        if (!rsp_valid || rsp_error !== expect_error ||
            (check_data && rsp_rdata !== expect_data))
            $fatal(1, "PLIC response addr=%h error=%b data=%h expected=%h",
                   addr, rsp_error, rsp_rdata, expect_data);
        repeat (3) begin
            @(posedge clk);
            if (!rsp_valid || rsp_error !== expect_error ||
                (check_data && rsp_rdata !== expect_data))
                $fatal(1, "PLIC response changed under backpressure");
        end
        @(negedge clk);
        rsp_ready = 1;
        @(posedge clk);
        @(negedge clk);
        rsp_ready = 0;
        if (rsp_valid) $fatal(1, "PLIC response failed to retire");
    endtask
    task automatic word_write(input logic [31:0] addr, input logic [31:0] data);
        access(1, addr, 2, data, 4'hf, 0, 0, 0);
    endtask
    task automatic word_read(input logic [31:0] addr, input logic [31:0] data);
        access(0, addr, 2, 0, 0, 0, data, 1);
    endtask

    initial begin
        req_valid = 0; req_write = 0; req_addr = 0;
        req_size = 0; req_wdata = 0; req_wstrb = 0;
        rsp_ready = 0; uart_irq = 0; dma_irq = 0;
        repeat (4) @(negedge clk);
        rst_n = 1;
        if (meip_irq || seip_irq) $fatal(1, "PLIC reset interrupts");
        word_read(32'h0c00_1000, 0);
        uart_irq = 1;
        dma_irq = 1;
        repeat (2) @(negedge clk);
        word_read(32'h0c00_1000, 32'h6);
        if (meip_irq || seip_irq) $fatal(1, "disabled source interrupted");
        word_write(32'h0c00_0004, 3);
        word_write(32'h0c00_0008, 5);
        word_write(32'h0c00_2000, 6);
        word_write(32'h0c00_2080, 6);
        if (!meip_irq || !seip_irq) $fatal(1, "enabled pending source not signalled");
        word_write(32'h0c20_0000, 5);
        if (meip_irq) $fatal(1, "threshold must be strict greater-than");
        word_write(32'h0c20_0000, 4);
        word_read(32'h0c20_0004, 2);
        if (meip_irq || !seip_irq) $fatal(1, "wrong context interrupted after claim");
        word_read(32'h0c00_1000, 2);
        word_read(32'h0c20_1004, 1);
        word_read(32'h0c00_1000, 0);
        if (meip_irq || seip_irq) $fatal(1, "claimed source still interrupted");
        word_write(32'h0c20_0004, 1); // Wrong context cannot complete S-owned source.
        word_write(32'h0c20_1004, 2); // Wrong context cannot complete M-owned source.
        word_read(32'h0c00_1000, 0);
        uart_irq = 0;
        dma_irq = 0;
        repeat (2) @(negedge clk);
        word_write(32'h0c20_0004, 2);
        word_write(32'h0c20_1004, 1);
        word_read(32'h0c00_1000, 0);
        uart_irq = 1;
        repeat (2) @(negedge clk);
        word_read(32'h0c00_1000, 2);
        if (meip_irq) $fatal(1, "below-threshold source notified M-mode");
        word_read(32'h0c20_0004, 1); // Polling claim ignores threshold.
        word_read(32'h0c00_1000, 0);
        word_write(32'h0c20_0004, 1);
        repeat (2) @(negedge clk);
        word_read(32'h0c00_1000, 2);
        word_write(32'h0c20_0000, 0);
        word_read(32'h0c20_0004, 1);
        word_read(32'h0c00_1000, 0);
        word_write(32'h0c20_0004, 1);
        repeat (2) @(negedge clk);
        word_read(32'h0c00_1000, 2); // Still-high level re-pends after completion.

        dma_irq = 1;
        word_write(32'h0c00_0008, 3);
        repeat (2) @(negedge clk);
        word_read(32'h0c00_1000, 6);
        word_read(32'h0c20_0004, 1); // Equal priority: lower ID wins.
        access(1, 32'h0c00_1000, 2, 6, 4'hf, 1, 0, 0);
        access(1, 32'h0c00_0004, 2, 7, 4'h1, 1, 0, 0);
        access(0, 32'h0c00_0005, 2, 0, 0, 1, 0, 0);
        word_read(32'h0c00_0004, 3);
        rst_n = 0;
        repeat (2) @(negedge clk);
        if (meip_irq || seip_irq || dut.pending != 0)
            $fatal(1, "PLIC reset did not clear state");
        $display("PASS: PLIC priorities, thresholds, M/S contexts, claim/complete, level re-pending and backpressure");
        $finish;
    end
endmodule
