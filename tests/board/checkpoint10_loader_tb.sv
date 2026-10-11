`timescale 1ns/1ps
module checkpoint10_loader_tb #(parameter integer COMPACT = 0);
    import axi128_pkg::*;
    localparam bit IS_COMPACT = COMPACT != 0;
    localparam integer TOTAL_WORDS = IS_COMPACT ? 12 : 8;
    logic [127:0] expected_rom [0:7];
    logic clk = 0, rst_n = 0, complete, error;
    logic [31:0] progress;
    axi_req_t req;
    axi_rsp_t memory_rsp, rsp;
    int fault = 0;
    always #5 clk = !clk;
    checkpoint10_image_loader #(.IMAGE_WORDS(TOTAL_WORDS), .ROM_WORDS(8),
        .FIRMWARE_WORDS(IS_COMPACT ? 3 : 8), .PAYLOAD_WORD(IS_COMPACT ? 7 : 8),
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
            8: if (req.araddr == 32'h80000030) rsp.rdata = memory_rsp.rdata ^ 128'd1;
            9: if (req.araddr == 32'h80000070) rsp.rdata = memory_rsp.rdata ^ 128'd1;
            default: ;
        endcase
    end
    // Check writes against an independent image specification, including the
    // two compact-ROM boundaries; self-consistent bad writes/readbacks fail.
    function automatic logic [127:0] expected_word(input int word_index);
        if (!IS_COMPACT || word_index < 3) return expected_rom[word_index];
        if (word_index < 7) return 128'b0;
        return expected_rom[word_index - 4];
    endfunction
    always @(posedge clk) if (rst_n && req.wvalid && rsp.wready) begin
        if (req.awaddr < 32'h80000000 || req.awaddr >= 32'h80000000 + TOTAL_WORDS * 16 ||
            req.awaddr[3:0] != 0 || req.wstrb != 16'hffff || !req.wlast)
            $fatal(1, "invalid image write");
        if (req.wdata !== expected_word(int'((req.awaddr - 32'h80000000) >> 4)))
            $fatal(1, "image differs from firmware/gap/payload specification at %h", req.awaddr);
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
        $readmemh("config/rom/checkpoint10_loader_test.mem", expected_rom);
        for (int reset_at = 3; reset_at <= 7; reset_at += 2) begin
            restart(0);
            wait (progress == 32'(reset_at));
        end
        restart(0);
        wait (complete || error);
        if (error || progress != TOTAL_WORDS) $fatal(1, "copy/restart failed");
        for (int word_index = 0; word_index < TOTAL_WORDS; word_index++) begin
            for (int byte_index = 0; byte_index < 16; byte_index++) begin
                if (memory.mem[word_index*16+byte_index] !==
                    8'(expected_word(word_index) >> (byte_index*8)))
                    $fatal(1, "DDR image differs at word %d byte %d", word_index, byte_index);
            end
        end
        repeat (20) @(negedge clk);
        if (req.awvalid || req.wvalid || req.arvalid) $fatal(1, "loader traffic after completion");
        for (int mode = 1; mode <= 9; mode++) begin
            restart(mode);
            wait (complete || error);
            if (!error || complete || progress != (mode == 8 ? 3 : mode == 9 ? 7 : 0))
                $fatal(1, "fault mode %d escaped", mode);
            repeat (20) @(negedge clk);
            if (!error || req.awvalid || req.wvalid || req.arvalid) $fatal(1, "failure did not remain stopped");
        end
        restart(0);
        wait (complete || error);
        if (error || progress != TOTAL_WORDS) $fatal(1, "recovery reset failed");
        $display("PASS: image layout (compact=%0d), gap/payload readback, restart, AXI errors and watchdog", COMPACT);
        $finish;
    end
endmodule
