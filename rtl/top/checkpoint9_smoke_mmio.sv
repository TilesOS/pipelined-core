`timescale 1ns/1ps
// Board-test ROM and diagnostics only. Standard devices remain checkpoint 10.
module checkpoint9_smoke_mmio #(
    parameter ROM_FILE = "checkpoint9_smoke.mem"
) (
    input logic clk, rst_n,
    input axi128_pkg::axi_req_t req,
    output axi128_pkg::axi_rsp_t rsp,
    input logic [31:0] icache_misses, dcache_misses, dcache_writebacks,
    input logic [31:0] icache_bypasses, dcache_bypasses, dma_trips, dma_errors,
    output logic [31:0] phase, result
);
    logic req_valid, req_ready, req_write, rsp_valid, rsp_ready, rsp_error;
    logic [31:0] addr, wdata, rdata;
    logic [1:0] size;
    logic [3:0] strb;
    logic pending;
    logic [31:0] rom [2048];
    initial $readmemh(ROM_FILE, rom);
    axi_peripheral_adapter adapter (
        .clk(clk), .rst_n(rst_n), .axi_req(req), .axi_rsp(rsp),
        .bus_req_valid(req_valid), .bus_req_ready(req_ready),
        .bus_req_write(req_write), .bus_req_addr(addr), .bus_req_size(size),
        .bus_req_wdata(wdata), .bus_req_wstrb(strb), .bus_rsp_valid(rsp_valid),
        .bus_rsp_ready(rsp_ready), .bus_rsp_rdata(rdata), .bus_rsp_error(rsp_error)
    );
    assign req_ready = !pending;
    assign rsp_valid = pending;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            pending <= 0; phase <= 0; result <= 0;
            rdata <= 0; rsp_error <= 0;
        end else begin
            if (rsp_valid && rsp_ready) pending <= 0;
            if (req_valid && req_ready) begin
                pending <= 1;
                rdata <= 0;
                rsp_error <= 0;
                if (size != 2 || addr[1:0] != 0 || (req_write && strb != 4'hf))
                    rsp_error <= 1;
                else if (!req_write && addr < 32'h2000)
                    rdata <= rom[addr[12:2]];
                else if (req_write) begin
                    case (addr)
                        32'h1003_0000: phase <= wdata;
                        32'h1003_0004: result <= wdata;
                        default: rsp_error <= 1;
                    endcase
                end else begin
                    case (addr)
                        32'h1003_0000: rdata <= phase;
                        32'h1003_0004: rdata <= result;
                        32'h1003_0010: rdata <= icache_misses;
                        32'h1003_0014: rdata <= dcache_misses;
                        32'h1003_0018: rdata <= dcache_writebacks;
                        32'h1003_001c: rdata <= icache_bypasses;
                        32'h1003_0020: rdata <= dcache_bypasses;
                        32'h1003_0024: rdata <= dma_trips;
                        32'h1003_0028: rdata <= dma_errors;
                        default: rsp_error <= 1;
                    endcase
                end
            end
        end
    end
endmodule
