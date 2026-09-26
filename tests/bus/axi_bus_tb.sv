`timescale 1ns/1ps
module axi_bus_tb;
    import axi128_pkg::*;
    logic core_clk = 0;
    logic mig_clk = 0;
    logic rst_n = 0;
    logic calib_complete = 0;
    logic masters_ready;
    integer core_half = 5;
    integer mig_half = 7;
    integer reset_beats = 1;
    initial begin
        void'($value$plusargs("core_half=%d", core_half));
        void'($value$plusargs("mig_half=%d", mig_half));
        void'($value$plusargs("reset_beats=%d", reset_beats));
        if (core_half < 2 || mig_half < 2 || core_half == mig_half)
            $fatal(1, "need unrelated clocks with half-period >= 2");
        if (reset_beats < 1 || reset_beats > 15) $fatal(1, "bad reset beat count");
    end
    always #(core_half) core_clk = ~core_clk;
    always #(mig_half) mig_clk = ~mig_clk;
    axi_req4_t masters;
    axi_rsp4_t replies;
    axi_req_t peripheral_req;
    axi_rsp_t peripheral_rsp;
    axi_req_t mig_req;
    axi_rsp_t mig_rsp;
    logic [1:0] read_owner, write_owner, active;
    logic [2:0] aw_level, w_level, ar_level, b_level, r_level;
    int completed = 0;
    int core_cycles = 0;
    int aw_wait [4];
    int ar_wait [4];
    int first_aw_count = 0;
    bit saw_read_write_overlap = 0;
    bit saw_w_fifo_backpressure = 0;
    axi_req_t prev_mig_req;
    axi_rsp_t prev_mig_rsp;
    bit prev_aw_stall, prev_w_stall, prev_ar_stall;
    bit prev_b_stall, prev_r_stall;
    logic start_traffic = 0;
    logic [3:0] traffic_done = 0;

    axi_subsystem subsystem(.core_clk(core_clk), .mig_clk(mig_clk),
        .rst_n(rst_n), .mig_calib_complete(calib_complete),
        .masters_ready(masters_ready), .master_req(masters), .master_rsp(replies),
        .peripheral_req(peripheral_req), .peripheral_rsp(peripheral_rsp),
        .mig_req(mig_req), .mig_rsp(mig_rsp), .read_owner_probe(read_owner),
        .write_owner_probe(write_owner), .active_probe(active),
        .aw_level(aw_level), .w_level(w_level), .ar_level(ar_level),
        .b_level(b_level), .r_level(r_level));
    axi_test_slave ddr(.clk(mig_clk), .rst_n(rst_n && calib_complete),
        .req(mig_req), .rsp(mig_rsp));
    axi_test_slave mmio(.clk(core_clk), .rst_n(rst_n && calib_complete),
        .req(peripheral_req), .rsp(peripheral_rsp));

    function automatic logic [127:0] pattern(input int m, input int t, input int beat);
        logic [127:0] value;
        for (int lane = 0; lane < 16; lane++)
            value[lane*8 +: 8] = 8'((m*41) ^ (t*19) ^ (beat*13) ^ lane);
        return value;
    endfunction

    task automatic write_burst(input int m, input logic [31:0] addr,
                               input int beats, input int tag,
                               input logic [1:0] expected_resp);
        @(negedge core_clk);
        masters[m].awvalid = 1;
        masters[m].awaddr = addr;
        masters[m].awlen = 4'(beats-1);
        masters[m].awsize = 3'd4;
        masters[m].awid = 4'(m+4);
        do @(posedge core_clk); while (!replies[m].awready);
        @(negedge core_clk);
        masters[m].awvalid = 0;
        for (int beat = 0; beat < beats; beat++) begin
            masters[m].wvalid = 1;
            masters[m].wdata = pattern(m, tag, beat);
            masters[m].wstrb = (beat % 3 == 0) ? 16'h5a5a : 16'hffff;
            masters[m].wlast = beat == beats-1;
            do @(posedge core_clk); while (!replies[m].wready);
            @(negedge core_clk);
        end
        masters[m].wvalid = 0;
        repeat (m+2) @(negedge core_clk);
        masters[m].bready = 1;
        do @(posedge core_clk); while (!replies[m].bvalid);
        if (replies[m].bresp !== expected_resp || replies[m].bid !== 4'(m+4))
            $fatal(1, "write response m=%0d addr=%h resp=%b id=%h", m, addr,
                replies[m].bresp, replies[m].bid);
        @(negedge core_clk);
        masters[m].bready = 0;
        completed++;
    endtask

    task automatic read_burst(input int m, input logic [31:0] addr,
                              input int beats, input int tag,
                              input logic [1:0] expected_resp,
                              input bit check_data);
        logic [127:0] expected;
        logic [7:0] expected_byte;
        @(negedge core_clk);
        masters[m].arvalid = 1;
        masters[m].araddr = addr;
        masters[m].arlen = 4'(beats-1);
        masters[m].arsize = 3'd4;
        masters[m].arid = 4'(m+4);
        do @(posedge core_clk); while (!replies[m].arready);
        @(negedge core_clk);
        masters[m].arvalid = 0;
        for (int beat = 0; beat < (expected_resp == AXI_OKAY ? beats : 1); beat++) begin
            masters[m].rready = 0;
            repeat ((beat+m)%4 + 1) @(negedge core_clk);
            masters[m].rready = 1;
            do @(posedge core_clk); while (!replies[m].rvalid);
            if (replies[m].rresp !== expected_resp ||
                replies[m].rid !== 4'(m+4) ||
                replies[m].rlast !== (beat == (expected_resp == AXI_OKAY ? beats-1 : 0)))
                $fatal(1, "read response m=%0d beat=%0d addr=%h", m, beat, addr);
            if (check_data) begin
                expected = pattern(m, tag, beat);
                for (int lane = 0; lane < 16; lane++) begin
                    if (beat % 3 != 0 || (((16'h5a5a >> lane) & 1) != 0))
                        expected_byte = expected[lane*8 +: 8];
                    else expected_byte = 8'((addr + 32'(beat*16+lane)) ^ 32'h5a);
                    if (replies[m].rdata[lane*8 +: 8] !== expected_byte)
                        $fatal(1, "read data m=%0d beat=%0d lane=%0d", m, beat, lane);
                end
            end
            @(negedge core_clk);
        end
        masters[m].rready = 0;
        completed++;
    endtask

    task automatic master_traffic(input int m);
        int beats;
        logic [31:0] addr;
        for (int t = 0; t < 8; t++) begin
            beats = ((m*7+t*3)%16)+1;
            addr = 32'h8000_0000 + 32'(m*4096 + (t+1)*256);
            write_burst(m, addr, beats, t, AXI_OKAY);
            read_burst(m, addr, beats, t, AXI_OKAY, 1);
        end
    endtask

    task automatic narrow_probe;
        @(negedge core_clk);
        masters[3].arvalid = 1;
        masters[3].araddr = 32'h1000_0001;
        masters[3].arlen = 0;
        masters[3].arsize = 0;
        masters[3].arid = 4'd7;
        do @(posedge core_clk); while (!replies[3].arready);
        @(negedge core_clk);
        masters[3].arvalid = 0;
        masters[3].rready = 1;
        do @(posedge core_clk); while (!replies[3].rvalid);
        if (replies[3].rresp !== AXI_OKAY || !replies[3].rlast ||
            replies[3].rid !== 4'd7)
            $fatal(1, "narrow MMIO route failed");
        @(negedge core_clk);
        masters[3].rready = 0;
        completed++;
    endtask

    always @(posedge core_clk) begin
        if (masters_ready) begin
            core_cycles++;
            if (active == 2'b11) saw_read_write_overlap = 1;
            if (w_level == 4) saw_w_fifo_backpressure = 1;
            if (core_cycles > 60000) $fatal(1, "watchdog: only %0d operations", completed);
            if (aw_level > 4 || w_level > 4 || ar_level > 4 ||
                b_level > 4 || r_level > 4) $fatal(1, "FIFO level overflow");
            for (int i = 0; i < 4; i++) begin
                if (first_aw_count < 4 && masters[i].awvalid && replies[i].awready) begin
                    if (i != first_aw_count)
                        $fatal(1, "first round-robin grant %0d was master %0d", first_aw_count, i);
                    first_aw_count++;
                end
                if (masters[i].awvalid && !replies[i].awready) aw_wait[i]++;
                else aw_wait[i] = 0;
                if (masters[i].arvalid && !replies[i].arready) ar_wait[i]++;
                else ar_wait[i] = 0;
                if (aw_wait[i] > 1000 || ar_wait[i] > 1000)
                    $fatal(1, "unfair arbitration for master %0d (read owner %0d, write owner %0d)",
                        i, read_owner, write_owner);
            end
        end
    end

    always @(posedge mig_clk) begin
        if (!rst_n || !calib_complete) begin
            prev_aw_stall = 0;
            prev_w_stall = 0;
            prev_ar_stall = 0;
            prev_b_stall = 0;
            prev_r_stall = 0;
        end else begin
            if (prev_aw_stall && (!mig_req.awvalid ||
                {mig_req.awaddr, mig_req.awlen, mig_req.awsize, mig_req.awid} !==
                {prev_mig_req.awaddr, prev_mig_req.awlen, prev_mig_req.awsize, prev_mig_req.awid}))
                $fatal(1, "AW changed under backpressure");
            if (prev_w_stall && (!mig_req.wvalid ||
                {mig_req.wdata, mig_req.wstrb, mig_req.wlast} !==
                {prev_mig_req.wdata, prev_mig_req.wstrb, prev_mig_req.wlast}))
                $fatal(1, "W changed under backpressure");
            if (prev_ar_stall && (!mig_req.arvalid ||
                {mig_req.araddr, mig_req.arlen, mig_req.arsize, mig_req.arid} !==
                {prev_mig_req.araddr, prev_mig_req.arlen, prev_mig_req.arsize, prev_mig_req.arid}))
                $fatal(1, "AR changed under backpressure");
            if (prev_b_stall && (!mig_rsp.bvalid ||
                {mig_rsp.bresp, mig_rsp.bid} !== {prev_mig_rsp.bresp, prev_mig_rsp.bid}))
                $fatal(1, "slave B changed under backpressure");
            if (prev_r_stall && (!mig_rsp.rvalid ||
                {mig_rsp.rdata, mig_rsp.rresp, mig_rsp.rlast, mig_rsp.rid} !==
                {prev_mig_rsp.rdata, prev_mig_rsp.rresp, prev_mig_rsp.rlast, prev_mig_rsp.rid}))
                $fatal(1, "slave R changed under backpressure");
            prev_aw_stall = mig_req.awvalid && !mig_rsp.awready;
            prev_w_stall = mig_req.wvalid && !mig_rsp.wready;
            prev_ar_stall = mig_req.arvalid && !mig_rsp.arready;
            prev_b_stall = mig_rsp.bvalid && !mig_req.bready;
            prev_r_stall = mig_rsp.rvalid && !mig_req.rready;
            prev_mig_req = mig_req;
            prev_mig_rsp = mig_rsp;
        end
    end

    for (genvar g = 0; g < 4; g++) begin : concurrent_master
        initial begin
            wait (start_traffic);
            master_traffic(g);
            traffic_done[g] = 1;
        end
    end

    initial begin
        foreach (masters[i]) masters[i] = '0;
        repeat (5) @(negedge core_clk);
        rst_n = 1;
        calib_complete = 1;
        wait (masters_ready);
        start_traffic = 1;
        wait (&traffic_done);
        if (first_aw_count != 4) $fatal(1, "did not exercise all four arbitration slots");
        if (!saw_read_write_overlap) $fatal(1, "no simultaneous read and write");
        if (!saw_w_fifo_backpressure) $fatal(1, "write FIFO never filled");
        // Decode rejection, peripheral routing, and a boundary-crossing burst.
        write_burst(0, 32'h8000_0f00, 16, 12, AXI_OKAY);
        read_burst(0, 32'h8000_0f00, 16, 12, AXI_OKAY, 1);
        write_burst(0, 32'h8800_0000, 2, 9, AXI_DECERR);
        read_burst(0, 32'h8000_0ff0, 2, 9, AXI_DECERR, 0);
        write_burst(1, 32'h0000_0000, 1, 9, AXI_DECERR);
        write_burst(2, 32'h1000_0000, 1, 9, AXI_OKAY);
        read_burst(2, 32'h1000_0000, 1, 9, AXI_OKAY, 1);
        write_burst(2, 32'h1000_0000, 2, 9, AXI_DECERR);
        narrow_probe();
        // Abort an accepted burst on asynchronous reset, then prove recovery.
        @(negedge core_clk);
        masters[0].awvalid = 1;
        masters[0].awaddr = 32'h8000_3000;
        masters[0].awlen = 4'd15;
        masters[0].awsize = 3'd4;
        do @(posedge core_clk); while (!replies[0].awready);
        @(negedge core_clk);
        masters[0].awvalid = 0;
        for (int beat = 0; beat < reset_beats; beat++) begin
            masters[0].wvalid = 1;
            masters[0].wdata = 128'(beat) + 128'd1;
            masters[0].wstrb = '1;
            masters[0].wlast = 0;
            do @(posedge core_clk); while (!replies[0].wready);
            @(negedge core_clk);
        end
        #1 calib_complete = 0;
        masters[0] = '0;
        repeat (5) @(negedge core_clk);
        calib_complete = 1;
        wait (masters_ready);
        repeat (10) @(negedge core_clk);
        write_burst(0, 32'h8000_3200, 3, 10, AXI_OKAY);
        read_burst(0, 32'h8000_3200, 3, 10, AXI_OKAY, 1);
        $display("PASS: %0d bus operations, clocks %0d/%0d, reset after %0d beats, W FIFO full=%0d",
                 completed, core_half, mig_half, reset_beats, saw_w_fifo_backpressure);
        $finish;
    end
endmodule
