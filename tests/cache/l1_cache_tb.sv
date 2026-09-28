`timescale 1ns/1ps
module l1_cache_tb;
    import axi128_pkg::*;
    import physical_memory_pkg::*;
    logic clk = 0;
    always #5 clk = ~clk;
    logic rst_n = 0;
    logic req_valid = 0, req_ready, req_write = 0;
    logic [31:0] req_addr = 0, req_wdata = 0;
    logic [1:0] req_size = 2;
    logic [3:0] req_wstrb = 15;
    logic rsp_valid, rsp_ready = 0;
    logic [31:0] rsp_rdata;
    logic [1:0] rsp_resp;
    logic clean_valid = 0, invalidate_valid = 0, maintenance_done, maintenance_fault;
    logic [31:0] misses, writebacks, bypasses;
    axi_req_t req, previous;
    axi_rsp_t rsp, memory_rsp;
    logic fail_read = 0, fail_write = 0, hold_b = 0;
    logic [1:0] previous_blocked;
    int operations = 0, cycles = 0, ar_count = 0, aw_count = 0;
    l1_cache cache (
        .clk(clk), .rst_n(rst_n), .req_valid(req_valid), .req_ready(req_ready),
        .req_write(req_write), .req_addr(req_addr), .req_wdata(req_wdata),
        .req_size(req_size), .req_wstrb(req_wstrb), .rsp_valid(rsp_valid), .rsp_ready(rsp_ready),
        .rsp_rdata(rsp_rdata), .rsp_resp(rsp_resp), .clean_valid(clean_valid),
        .invalidate_valid(invalidate_valid), .maintenance_done(maintenance_done),
        .maintenance_fault(maintenance_fault), .axi_req(req), .axi_rsp(rsp),
        .miss_count(misses), .writeback_count(writebacks), .bypass_count(bypasses)
    );
    axi_req_t memory_req;
    always_comb begin
        memory_req = req;
        if (hold_b) memory_req.bready = 0;
        rsp = memory_rsp;
        if (hold_b) rsp.bvalid = 0;
        if (fail_read) rsp.rresp = AXI_SLVERR;
        if (fail_write) rsp.bresp = AXI_SLVERR;
    end
    cache_test_memory #(.BYTES(65536)) memory (.clk(clk), .rst_n(rst_n), .req(memory_req), .rsp(memory_rsp));
    always @(posedge clk) begin
        cycles <= cycles + 1;
        if (cycles > 200000) $fatal(1, "cache test timeout");
        if (rst_n) begin
            if (req.arvalid && rsp.arready) begin
                ar_count <= ar_count + 1;
                if (cacheable(req.araddr) && (req.arlen != 1 || req.arsize != 4 || req.araddr[4:0] != 0))
                    $fatal(1, "cache refill geometry");
                if (!cacheable(req.araddr) && req.arlen != 0) $fatal(1, "uncached burst");
            end
            if (req.awvalid && rsp.awready) begin
                aw_count <= aw_count + 1;
                if (cacheable(req.awaddr) && (req.awlen != 1 || req.awsize != 4 || req.awaddr[4:0] != 0))
                    $fatal(1, "cache writeback geometry");
            end
            if (previous_blocked[0] && (!req.arvalid || {req.araddr,req.arlen,req.arsize} != {previous.araddr,previous.arlen,previous.arsize}))
                $fatal(1, "AR changed under backpressure");
            if (previous_blocked[1] && (!req.wvalid || {req.wdata,req.wstrb,req.wlast} != {previous.wdata,previous.wstrb,previous.wlast}))
                $fatal(1, "W changed under backpressure");
            previous <= req;
            previous_blocked <= {req.wvalid && !rsp.wready, req.arvalid && !rsp.arready};
        end else previous_blocked <= 0;
    end
    task automatic access(input bit write_access, input logic [31:0] address,
        input logic [31:0] value, input logic [1:0] size,
        input logic [31:0] expected, input logic [1:0] expected_resp = AXI_OKAY);
        @(negedge clk);
        req_valid = 1; req_write = write_access; req_addr = address;
        req_wdata = value; req_size = size; req_wstrb = 4'( (1 << (1 << size)) - 1 );
        do @(posedge clk); while (!req_ready);
        @(negedge clk); req_valid = 0;
        do @(negedge clk); while (!rsp_valid);
        if (rsp_resp != expected_resp || (!write_access && expected_resp == AXI_OKAY &&
            (rsp_rdata & (size == 0 ? 32'hff : size == 1 ? 32'hffff : 32'hffff_ffff)) != expected))
            $fatal(1, "cache access %08x got %08x resp %x expected %08x resp %x", address, rsp_rdata, rsp_resp, expected, expected_resp);
        repeat (3) begin
            @(negedge clk);
            if (!rsp_valid || rsp_resp != expected_resp) $fatal(1, "response not held");
        end
        rsp_ready = 1;
        @(negedge clk); rsp_ready = 0;
        operations++;
    endtask
    task automatic maintain(input bit invalidate_cache, input bit expected_fault = 0);
        @(negedge clk); clean_valid = !invalidate_cache; invalidate_valid = invalidate_cache;
        do @(negedge clk); while (!maintenance_done);
        if (maintenance_fault != expected_fault) $fatal(1, "maintenance fault mismatch");
        @(negedge clk); clean_valid = 0; invalidate_valid = 0;
        @(negedge clk);
    endtask
    function automatic logic [31:0] memword(input int offset);
        return {memory.mem[offset+3], memory.mem[offset+2], memory.mem[offset+1], memory.mem[offset]};
    endfunction
    initial begin
        int before_reads, before_writes;
        logic [31:0] snapshot;
        repeat (4) @(negedge clk); rst_n = 1;
        // Exact physical boundaries; no virtual-address aliases are accepted.
        if (!cacheable(32'h8000_0000) || !cacheable(32'h877f_ffff) || cacheable(32'h8780_0000) ||
            cacheable(32'h87ff_ffff) || cacheable(32'h1000_0000)) $fatal(1, "physical attributes");
        access(0, 32'h8000_0000, 0, 2, memword(0));
        before_reads = ar_count;
        access(0, 32'h8000_001c, 0, 2, memword(28));
        if (ar_count != before_reads) $fatal(1, "line hit caused refill");
        access(1, 32'h8000_0003, 32'hab, 0, 0);
        access(1, 32'h8000_0006, 32'hcdef, 1, 0);
        access(0, 32'h8000_0000, 0, 2, 32'hab58_5b5a);
        access(0, 32'h8000_0004, 0, 2, 32'hcdef_5f5e);
        // Three tags in the same set force a dirty LRU eviction. A second-way
        // hit changes the victim; an incorrect FIFO replacement fails here.
        access(1, 32'h8000_1000, 32'h1122_3344, 2, 0);
        access(0, 32'h8000_0000, 0, 2, 32'hab58_5b5a);
        access(1, 32'h8000_2000, 32'h5566_7788, 2, 0);
        if (memword(4096) != 32'h1122_3344 || memword(0) == 32'hab58_5b5a)
            $fatal(1, "wrong dirty victim written back");
        access(0, 32'h8000_1000, 0, 2, 32'h1122_3344);
        // Fill/dirty every set in both ways, including the last maintenance
        // entry and the second beat of each line.
        for (int way = 0; way < 2; way++)
            for (int set_no = 0; set_no < 128; set_no++)
                access(1, 32'h8000_8000 + 32'(way*4096 + set_no*32 + 28), 32'hcafe_0000 + 32'(way*128+set_no), 2, 0);
        // Delay the last B response: clean must not acknowledge early.
        fork
            begin
                wait (cache.scan_index == 255 && cache.state == cache.WB_B);
                @(negedge clk); hold_b = 1;
                repeat (20) begin @(negedge clk); if (maintenance_done) $fatal(1, "early clean acknowledgement"); end
                hold_b = 0;
            end
            maintain(0);
        join
        for (int way = 0; way < 2; way++)
            for (int set_no = 0; set_no < 128; set_no++)
                if (memword(32768 + way*4096 + set_no*32 + 28) != 32'hcafe_0000 + 32'(way*128+set_no))
                    $fatal(1, "clean omitted dirty line %0d/%0d", way, set_no);
        before_writes = aw_count; maintain(0);
        if (aw_count != before_writes) $fatal(1, "clean cache wrote again");
        // Uncached accesses see an external change on the next operation and
        // use one 128-bit DDR beat with only the requested byte lanes enabled.
        before_reads = ar_count;
        access(1, 32'h8780_004f, 32'h7a, 0, 0);
        if (memory.mem[79] != 8'h7a) $fatal(1, "uncached byte strobe");
        access(0, 32'h8780_004f, 0, 0, 32'h7a);
        @(negedge clk); memory.mem[79] = 8'h39;
        access(0, 32'h8780_004f, 0, 0, 32'h39);
        if (ar_count != before_reads + 2) $fatal(1, "DMA pool was cached");
        access(1, 32'h87ff_fffc, 32'h9876_5432, 2, 0);
        access(0, 32'h87ff_fffc, 0, 2, 32'h9876_5432);
        access(1, 32'h1000_0003, 32'h99, 0, 0);
        if (memory.mem[3] != 8'h99) $fatal(1, "narrow peripheral address");
        before_reads = ar_count; before_writes = aw_count;
        access(0, 32'h8800_0000, 0, 2, 0, AXI_DECERR);
        access(1, 32'h0000_0000, 1, 2, 0, AXI_DECERR);
        if (ar_count != before_reads || aw_count != before_writes) $fatal(1, "invalid access reached AXI");
        // Failed refill must not install a valid line; failed writeback must
        // retain dirty data and allow a later clean retry.
        fail_read = 1;
        access(0, 32'h8000_4000, 0, 2, 0, AXI_SLVERR);
        fail_read = 0; before_reads = ar_count;
        access(0, 32'h8000_4000, 0, 2, memword(16384));
        if (ar_count != before_reads + 1) $fatal(1, "failed refill installed a line");
        access(1, 32'h8000_4000, 32'hdead_beef, 2, 0);
        fail_write = 1; maintain(0, 1); fail_write = 0;
        before_writes = aw_count; maintain(0);
        if (aw_count != before_writes + 1 || memword(16384) != 32'hdead_beef) $fatal(1, "dirty data lost after error");
        snapshot = memword(16384); before_reads = ar_count; maintain(1);
        access(0, 32'h8000_4000, 0, 2, snapshot);
        if (ar_count != before_reads + 1) $fatal(1, "invalidate failed");
        // Last cached byte line is legal; adjacent DMA line bypasses.
        access(1, 32'h877f_fffc, 32'h1234_5678, 2, 0);
        maintain(0);
        $display("PASS: %0d L1 operations, two-way eviction, all 256 dirty lines, physical bypass, response hold and AXI error recovery", operations);
        $finish;
    end
endmodule
