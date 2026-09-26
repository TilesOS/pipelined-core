`timescale 1ns/1ps
module axi_bridge_tb;
    import axi128_pkg::*;
    logic clk = 0;
    logic rst_n = 0;
    always #5 clk = ~clk;
    logic req_valid, req_ready, req_write, req_narrow, rsp_valid, rsp_ready;
    logic [31:0] req_addr, req_wdata, rsp_rdata;
    logic [1:0] req_size, rsp_resp;
    logic [3:0] req_wstrb;
    axi_req_t axi_req;
    axi_rsp_t axi_rsp;
    int operations = 0;
    int cycles = 0;

    axi_width_bridge #(.MASTER_ID(4'd2)) bridge (
        .clk(clk), .rst_n(rst_n), .req_valid(req_valid), .req_ready(req_ready),
        .req_write(req_write), .req_narrow(req_narrow),
        .req_addr(req_addr), .req_size(req_size),
        .req_wdata(req_wdata), .req_wstrb(req_wstrb), .rsp_valid(rsp_valid),
        .rsp_ready(rsp_ready), .rsp_rdata(rsp_rdata), .rsp_resp(rsp_resp),
        .axi_req(axi_req), .axi_rsp(axi_rsp));
    axi_test_slave slave(.clk(clk), .rst_n(rst_n), .req(axi_req), .rsp(axi_rsp));

    task automatic access(input bit is_write, input logic [31:0] addr,
                          input logic [1:0] size, input logic [31:0] data,
                          input logic [3:0] strobe, input logic [1:0] response,
                          input logic [31:0] value, input logic [31:0] mask);
        @(negedge clk);
        req_valid = 1;
        req_write = is_write;
        req_narrow = 0;
        req_addr = addr;
        req_size = size;
        req_wdata = data;
        req_wstrb = strobe;
        do @(posedge clk); while (!req_ready);
        @(negedge clk);
        req_valid = 0;
        do @(posedge clk); while (!rsp_valid);
        if (rsp_resp !== response || ((rsp_rdata & mask) !== value))
            $fatal(1, "bridge addr=%h write=%b got resp=%b data=%h", addr,
                is_write, rsp_resp, rsp_rdata);
        repeat (3) begin
            @(posedge clk);
            if (!rsp_valid || rsp_resp !== response) $fatal(1, "response did not hold");
        end
        @(negedge clk);
        rsp_ready = 1;
        @(posedge clk);
        @(negedge clk);
        rsp_ready = 0;
        operations++;
    endtask

    always @(posedge clk) begin
        cycles++;
        if (cycles > 5000) $fatal(1, "bridge watchdog");
        if (rst_n && (axi_req.awvalid || axi_req.arvalid) &&
            (axi_req.awaddr[3:0] != 0 || axi_req.araddr[3:0] != 0 ||
             axi_req.awsize != 3'd4 || axi_req.arsize != 3'd4))
            $fatal(1, "unaligned 128-bit AXI beat");
    end

    initial begin
        req_valid = 0;
        req_write = 0;
        req_narrow = 0;
        req_addr = 0;
        req_size = 0;
        req_wdata = 0;
        req_wstrb = 0;
        rsp_ready = 0;
        repeat (4) @(negedge clk);
        rst_n = 1;
        access(1, 32'h8000_0001, 0, 32'h0000_00ab, 4'b0001, AXI_OKAY, 0, 0);
        access(1, 32'h8000_0002, 1, 32'h0000_cdef, 4'b0011, AXI_OKAY, 0, 0);
        access(1, 32'h8000_0004, 2, 32'h1234_5678, 4'b1111, AXI_OKAY, 0, 0);
        access(0, 32'h8000_0000, 2, 0, 0, AXI_OKAY, 32'hcdef_ab5a, 32'hffff_ffff);
        access(0, 32'h8000_0001, 0, 0, 0, AXI_OKAY, 32'h0000_00ab, 32'h0000_00ff);
        access(0, 32'h8000_0004, 2, 0, 0, AXI_OKAY, 32'h1234_5678, 32'hffff_ffff);
        access(1, 32'h8000_000f, 0, 32'h0000_00ed, 4'b0001, AXI_OKAY, 0, 0);
        access(0, 32'h8000_000f, 0, 0, 0, AXI_OKAY, 32'h0000_00ed, 32'h0000_00ff);
        access(0, 32'h8000_0001, 1, 0, 0, AXI_SLVERR, 0, 0);
        access(1, 32'h8000_0002, 2, 32'hffff_ffff, 4'b1111, AXI_SLVERR, 0, 0);
        $display("PASS: %0d bridge operations, byte lanes, errors, response hold", operations);
        $finish;
    end
endmodule
