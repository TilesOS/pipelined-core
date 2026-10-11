`timescale 1ns/1ps
module axi_peripheral_tb;
    import axi128_pkg::*;
    logic clk = 0;
    logic rst_n = 0;
    always #5 clk = ~clk;
    logic req_valid, req_ready, req_write, rsp_valid, rsp_ready;
    logic [31:0] req_addr, req_wdata, rsp_rdata;
    logic [1:0] req_size, rsp_resp;
    logic [3:0] req_wstrb;
    axi_req_t axi_req;
    axi_rsp_t axi_rsp;
    logic bus_req_valid, bus_req_ready, bus_req_write;
    logic [31:0] bus_req_addr, bus_req_wdata;
    logic [1:0] bus_req_size;
    logic [3:0] bus_req_wstrb;
    logic bus_rsp_valid, bus_rsp_ready, bus_rsp_error;
    logic [31:0] bus_rsp_rdata;
    logic [7:0] bytes [16];
    logic pending;
    int bus_count = 0;
    int cycles = 0;

    axi_width_bridge #(.MASTER_ID(4'd1)) bridge (
        .clk(clk), .rst_n(rst_n), .req_valid(req_valid), .req_ready(req_ready),
        .req_write(req_write), .req_narrow(1'b1), .req_addr(req_addr),
        .req_size(req_size), .req_wdata(req_wdata), .req_wstrb(req_wstrb),
        .rsp_valid(rsp_valid), .rsp_ready(rsp_ready), .rsp_rdata(rsp_rdata),
        .rsp_resp(rsp_resp), .axi_req(axi_req), .axi_rsp(axi_rsp));
    axi_peripheral_adapter adapter (
        .clk(clk), .rst_n(rst_n), .axi_req(axi_req), .axi_rsp(axi_rsp),
        .bus_req_valid(bus_req_valid), .bus_req_ready(bus_req_ready),
        .bus_req_write(bus_req_write), .bus_req_addr(bus_req_addr),
        .bus_req_size(bus_req_size), .bus_req_wdata(bus_req_wdata),
        .bus_req_wstrb(bus_req_wstrb), .bus_rsp_valid(bus_rsp_valid),
        .bus_rsp_ready(bus_rsp_ready), .bus_rsp_rdata(bus_rsp_rdata),
        .bus_rsp_decode_error(1'b0), .bus_rsp_error(bus_rsp_error));
    assign bus_req_ready = !pending && cycles[0];
    assign bus_rsp_valid = pending && cycles[1];
    assign bus_rsp_error = 0;

    always @(posedge clk) begin
        cycles++;
        if (cycles > 2000) $fatal(1, "peripheral watchdog");
    end
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending <= 0;
            bus_rsp_rdata <= 0;
        end else begin
            if (bus_req_valid && bus_req_ready) begin
                if (bus_req_addr < 32'h1000_0000 || bus_req_addr >= 32'h1000_0010)
                    $fatal(1, "unexpected peripheral address");
                if ((bus_req_addr & ((32'd1 << bus_req_size)-1)) != 0)
                    $fatal(1, "misaligned peripheral request");
                if (bus_req_write) begin
                    for (int i = 0; i < 4; i++)
                        if (bus_req_wstrb[i]) bytes[(int'(bus_req_addr[3:0])+i)%16] <=
                            bus_req_wdata[i*8 +: 8];
                end else begin
                    for (int i = 0; i < 4; i++)
                        bus_rsp_rdata[i*8 +: 8] <= bytes[(int'(bus_req_addr[3:0])+i)%16];
                end
                pending <= 1;
                bus_count++;
            end
            if (bus_rsp_valid && bus_rsp_ready) pending <= 0;
        end
    end

    task automatic access(input bit is_write, input logic [31:0] addr,
                          input logic [1:0] size, input logic [31:0] data,
                          input logic [3:0] strobe, input logic [1:0] expected_resp,
                          input logic [31:0] expected_data,
                          input logic [31:0] mask, input bit reaches_device);
        int before_count;
        before_count = bus_count;
        @(negedge clk);
        req_valid = 1;
        req_write = is_write;
        req_addr = addr;
        req_size = size;
        req_wdata = data;
        req_wstrb = strobe;
        do @(posedge clk); while (!req_ready);
        @(negedge clk);
        req_valid = 0;
        do @(posedge clk); while (!rsp_valid);
        if (rsp_resp !== expected_resp || (rsp_rdata & mask) !== expected_data)
            $fatal(1, "peripheral access addr=%h got resp=%b data=%h", addr,
                rsp_resp, rsp_rdata);
        if (bus_count != before_count + int'(reaches_device))
            $fatal(1, "device accessed %0d times", bus_count - before_count);
        @(negedge clk);
        rsp_ready = 1;
        @(posedge clk);
        @(negedge clk);
        rsp_ready = 0;
    endtask

    initial begin
        req_valid = 0;
        req_write = 0;
        req_addr = 0;
        req_size = 0;
        req_wdata = 0;
        req_wstrb = 0;
        rsp_ready = 0;
        for (int i = 0; i < 16; i++) bytes[i] = 8'(i + 1);
        repeat (4) @(negedge clk);
        rst_n = 1;
        access(1, 32'h1000_0001, 0, 32'h0000_00ab, 1, AXI_OKAY, 0, 0, 1);
        access(0, 32'h1000_0001, 0, 0, 0, AXI_OKAY, 32'h0000_00ab, 32'hff, 1);
        access(1, 32'h1000_0002, 1, 32'h0000_cdef, 3, AXI_OKAY, 0, 0, 1);
        access(0, 32'h1000_0002, 1, 0, 0, AXI_OKAY, 32'h0000_cdef, 32'hffff, 1);
        access(1, 32'h1000_0004, 2, 32'h1234_5678, 15, AXI_OKAY, 0, 0, 1);
        access(0, 32'h1000_0004, 2, 0, 0, AXI_OKAY, 32'h1234_5678, 32'hffff_ffff, 1);
        access(0, 32'h1000_0001, 1, 0, 0, AXI_SLVERR, 0, 0, 0);
        $display("PASS: seven narrow peripheral accesses, exact byte address and one device request each");
        $finish;
    end
endmodule
