`timescale 1ns/1ps
module checkpoint10_loader_tb;
    import axi128_pkg::*;
    logic clk = 0, rst_n = 0, complete, error;
    logic [31:0] progress;
    axi_req_t req;
    axi_rsp_t memory_rsp, rsp;
    int fault = 0;
    always #5 clk = !clk;
    checkpoint10_image_loader #(.IMAGE_WORDS(8),
        .IMAGE_FILE("config/rom/checkpoint10_loader_test.mem"), .TIMEOUT_CYCLES(256)) loader (
        .clk(clk), .rst_n(rst_n), .req(req), .rsp(rsp),
        .complete(complete), .error(error), .progress(progress)
    );
    cache_test_memory #(.BYTES(256), .LINEAR_DDR(1)) memory (
        .clk(clk), .rst_n(rst_n), .req(req), .rsp(memory_rsp)
    );
    always_comb begin
        rsp = memory_rsp;
        case (fault)
            1: rsp.bresp = AXI_SLVERR;
            2: rsp.rdata = memory_rsp.rdata ^ 128'd1;
            3: rsp.rid = 3;
            4: rsp.rlast = 0;
            5: rsp.rresp = AXI_DECERR;
            6: rsp = '0;
            7: rsp.bid = 3;
            default: ;
        endcase
    end
    task automatic restart(input int mode);
        @(negedge clk); rst_n = 0; fault = mode;
        repeat (5) @(negedge clk);
        if (complete || error || progress != 0) $fatal(1, "loader did not reset");
        rst_n = 1;
    endtask
    initial begin
        #200000; $fatal(1, "loader TB watchdog");
    end
    initial begin
        restart(0);
        wait (progress == 3);
        restart(0);
        wait (complete || error);
        if (error || progress != 8) $fatal(1, "copy/restart failed");
        repeat (20) @(negedge clk);
        if (req.awvalid || req.wvalid || req.arvalid) $fatal(1, "loader traffic after completion");
        for (int mode = 1; mode <= 7; mode++) begin
            restart(mode);
            wait (complete || error);
            if (!error || complete || progress != 0) $fatal(1, "fault mode %d escaped", mode);
            repeat (20) @(negedge clk);
            if (!error || req.awvalid || req.wvalid || req.arvalid) $fatal(1, "failure did not remain stopped");
        end
        restart(0);
        wait (complete || error);
        if (error || progress != 8) $fatal(1, "recovery reset failed");
        $display("PASS: image readback, restart, B/R errors, corrupt data, wrong IDs/RLAST and watchdog keep CPU release blocked");
        $finish;
    end
endmodule
