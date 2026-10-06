`timescale 1ns/1ps
module checkpoint10_mmio_tb;
    import axi128_pkg::*;
    logic clk = 0, rst_n = 0, tx, msip, mtip, meip, seip;
    always #5 clk = ~clk;
    axi_req_t req;
    axi_rsp_t rsp;
    checkpoint10_mmio #(.UART_DEFAULT_DIVISOR(1)) dut (
        .clk(clk), .rst_n(rst_n), .uart_rx(1'b1), .dma_irq(1'b0), .uart_tx(tx),
        .time_value(), .msip_irq(msip), .mtip_irq(mtip), .meip_irq(meip), .seip_irq(seip), .axi_req(req), .axi_rsp(rsp)
    );
    initial begin #1000000; $fatal(1, "MMIO watchdog"); end
    task automatic access(input bit write_op, input logic [31:0] addr, input logic [2:0] size,
                          input logic [31:0] data, input logic [1:0] response = AXI_OKAY, input bit bad_strobe = 0);
        logic [127:0] captured;
        @(negedge clk); req = '0;
        if (write_op) begin
            req.awvalid = 1; req.awaddr = addr; req.awsize = size; req.awid = 5;
            do @(posedge clk); while (!rsp.awready);
            @(negedge clk); req.awvalid = 0;
            req.wvalid = 1; req.wlast = 1;
            req.wdata = {96'b0, data} << (8 * addr[3:0]);
            req.wstrb = ((16'hffff >> (16 - (1 << size))) << addr[3:0]) | (bad_strobe ? 16'h8000 : 0);
            do @(posedge clk); while (!rsp.wready);
            @(negedge clk); req.wvalid = 0;
            wait (rsp.bvalid);
            repeat (4) begin
                @(negedge clk);
                if (!rsp.bvalid || rsp.bresp != response || rsp.bid != 5) $fatal(1, "MMIO write %h", addr);
            end
            req.bready = 1; @(negedge clk); req.bready = 0;
        end else begin
            req.arvalid = 1; req.araddr = addr; req.arsize = size; req.arid = 7;
            do @(posedge clk); while (!rsp.arready);
            @(negedge clk); req.arvalid = 0;
            wait (rsp.rvalid); captured = rsp.rdata;
            repeat (4) begin
                @(negedge clk);
                if (!rsp.rvalid || rsp.rresp != response || rsp.rid != 7 || !rsp.rlast || rsp.rdata != captured)
                    $fatal(1, "MMIO read %h", addr);
            end
            if (response == AXI_OKAY && (captured >> (8 * addr[3:0])) != {96'b0, data})
                $fatal(1, "MMIO read %h data=%h expected=%h", addr, captured, data);
            req.rready = 1; @(negedge clk); req.rready = 0;
        end
    endtask
    initial begin
        req = '0; repeat (4) @(negedge clk); rst_n = 1;
        access(1, 32'h02000000, 2, 1); if (!msip) $fatal(1, "MMIO MSIP");
        access(0, 32'h02000000, 2, 1);
        access(1, 32'h02004004, 2, 32'hffffffff);
        access(1, 32'h02004000, 2, 0); access(1, 32'h02004004, 2, 0);
        if (!mtip) $fatal(1, "MMIO timer compare");
        access(1, 32'h10000007, 0, 32'ha5); access(0, 32'h10000007, 0, 32'ha5);
        access(1, 32'h0c000004, 2, 1); access(1, 32'h0c002000, 2, 2);
        access(1, 32'h0c002080, 2, 2);
        access(1, 32'h10000001, 0, 2); repeat (3) @(negedge clk);
        if (!meip || !seip) $fatal(1, "UART to PLIC contexts");
        access(0, 32'h0c201004, 2, 1);
        if (meip || seip) $fatal(1, "claim repeated under held AXI response");
        access(0, 32'h10000002, 0, 2); // acknowledge THRE before completion
        access(1, 32'h0c201004, 2, 1); repeat (3) @(negedge clk);
        if (meip || seip) $fatal(1, "unexpected level re-pending");
        access(1, 32'h10000007, 0, 0, AXI_SLVERR, 1);
        access(0, 32'h10000007, 0, 32'ha5);
        access(0, 32'h10000005, 2, 0, AXI_SLVERR);
        access(0, 32'h02000001, 0, 0, AXI_SLVERR);
        access(0, 32'h10000008, 0, 0, AXI_SLVERR);
        access(0, 32'h10010000, 2, 0, AXI_DECERR);
        access(1, 32'h10020000, 2, 0, AXI_DECERR);
        access(0, 32'h20000000, 2, 0, AXI_DECERR);
        $display("PASS: MMIO narrow AXI lanes, device errors/DECERR, CLINT timer, UART-to-PLIC and held claim response"); $finish;
    end
endmodule
