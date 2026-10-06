timeunit 1ns;
timeprecision 1ps;
module clint_tb;
    logic clk = 0;
    logic rst_n = 0;
    always #5 clk = ~clk;

    logic req_valid, req_ready, req_write, rsp_valid, rsp_ready, rsp_error;
    logic [31:0] req_addr, req_wdata, rsp_rdata;
    logic [1:0] req_size;
    logic [3:0] req_wstrb;
    logic msip_irq, mtip_irq;
    int cycles = 0;

    clint #(.CYCLES_PER_TICK(50)) dut (
        .clk(clk), .rst_n(rst_n), .bus_req_valid(req_valid), .bus_req_ready(req_ready),
        .bus_req_write(req_write), .bus_req_addr(req_addr), .bus_req_size(req_size),
        .bus_req_wdata(req_wdata), .bus_req_wstrb(req_wstrb),
        .bus_rsp_valid(rsp_valid), .bus_rsp_ready(rsp_ready),
        .bus_rsp_rdata(rsp_rdata), .bus_rsp_error(rsp_error),
        .msip_irq(msip_irq), .mtip_irq(mtip_irq)
    );

    always @(posedge clk) begin
        cycles++;
        if (cycles > 5000) $fatal(1, "CLINT watchdog");
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
            $fatal(1, "CLINT response addr=%h error=%b data=%h", addr, rsp_error, rsp_rdata);
        repeat (3) begin
            @(posedge clk);
            if (!rsp_valid || rsp_error !== expect_error ||
                (check_data && rsp_rdata !== expect_data))
                $fatal(1, "CLINT response changed under backpressure");
        end
        @(negedge clk);
        rsp_ready = 1;
        @(posedge clk);
        @(negedge clk);
        rsp_ready = 0;
        if (rsp_valid) $fatal(1, "CLINT response failed to retire");
    endtask

    task automatic word_write(input logic [31:0] addr, input logic [31:0] data);
        access(1, addr, 2, data, 4'hf, 0, 0, 0);
    endtask

    initial begin
        req_valid = 0;
        req_write = 0;
        req_addr = 0;
        req_size = 0;
        req_wdata = 0;
        req_wstrb = 0;
        rsp_ready = 0;
        repeat (4) @(negedge clk);
        rst_n = 1;
        if (msip_irq || mtip_irq || dut.mtime !== 0 || dut.mtimecmp !== '1)
            $fatal(1, "CLINT reset state");
        repeat (50) @(posedge clk);
        #1;
        if (dut.mtime !== 1) $fatal(1, "mtime divider expected one tick");
        access(0, 32'h0200_0000, 2, 0, 0, 0, 0, 1);
        word_write(32'h0200_0000, 32'hffff_ffff);
        if (!msip_irq) $fatal(1, "MSIP did not assert");
        access(0, 32'h0200_0000, 2, 0, 0, 0, 1, 1);
        access(1, 32'h0200_0000, 0, 0, 4'h1, 1, 0, 0);
        if (!msip_irq) $fatal(1, "bad size mutated MSIP");
        access(1, 32'h0200_0000, 2, 0, 4'h1, 1, 0, 0);
        if (!msip_irq) $fatal(1, "bad strobe mutated MSIP");
        access(0, 32'h0200_0001, 2, 0, 0, 1, 0, 0);
        access(0, 32'h0200_0010, 2, 0, 0, 1, 0, 0);
        word_write(32'h0200_0000, 0);
        if (msip_irq) $fatal(1, "MSIP did not clear");

        word_write(32'h0200_bffc, 1);
        word_write(32'h0200_bff8, 32'hffff_fff0);
        word_write(32'h0200_4004, 0);
        word_write(32'h0200_4000, 0);
        if (!mtip_irq) $fatal(1, "already-pending timer did not assert");
        // Required RV32 safe sequence: high=-1, low=desired, high=desired.
        word_write(32'h0200_4004, 32'hffff_ffff);
        if (mtip_irq) $fatal(1, "safe high sentinel did not clear MTIP");
        word_write(32'h0200_4000, 32'hffff_fff5);
        if (mtip_irq) $fatal(1, "safe low write spuriously set MTIP");
        word_write(32'h0200_4004, 1);
        if (mtip_irq) $fatal(1, "future compare spuriously set MTIP");
        word_write(32'h0200_bff8, 32'hffff_fff5);
        if (!mtip_irq) $fatal(1, "mtime equality did not set MTIP");

        word_write(32'h0200_4004, 2);
        word_write(32'h0200_4000, 1);
        word_write(32'h0200_bffc, 1);
        word_write(32'h0200_bff8, 32'hffff_fffe);
        if (mtip_irq) $fatal(1, "timer fired before 64-bit rollover");
        wait (dut.mtime == 64'h0000_0002_0000_0000);
        #1;
        if (mtip_irq) $fatal(1, "timer fired one tick before compare");
        wait (mtip_irq);
        if (dut.mtime != 64'h0000_0002_0000_0001)
            $fatal(1, "timer did not fire at rollover equality");
        access(0, 32'h0200_4000, 2, 0, 0, 0, 1, 1);
        access(0, 32'h0200_4004, 2, 0, 0, 0, 2, 1);
        rst_n = 0;
        repeat (2) @(negedge clk);
        if (msip_irq || mtip_irq || dut.mtime !== 0 || dut.mtimecmp !== '1)
            $fatal(1, "CLINT reset did not clear state");
        $display("PASS: CLINT 1 MHz divider, MSIP, safe RV32 mtimecmp writes, 64-bit rollover and backpressure");
        $finish;
    end
endmodule
