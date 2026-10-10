`timescale 1ns/1ps
// Background traffic confined to a pool region disjoint from the CPU test.
module checkpoint9_smoke_dma (
    input logic clk, rst_n, stop,
    output axi128_pkg::axi_req_t req,
    input axi128_pkg::axi_rsp_t rsp,
    output logic [31:0] trips, errors
);
    import axi128_pkg::*;
    typedef enum logic [2:0] {AW, W, B, AR, R, STOPPED} state_t;
    state_t state;
    logic [127:0] pattern;
    assign pattern = {trips ^ 32'h9abcdef0, trips ^ 32'h56781234,
                      trips ^ 32'hfedcba98, trips ^ 32'h76543210};
    always_comb begin
        req = '0;
        req.awvalid = state == AW && !stop;
        req.awaddr = 32'h87ff_8000; req.awsize = 4;
        req.wvalid = state == W; req.wdata = pattern;
        req.wstrb = '1; req.wlast = 1; req.bready = state == B;
        req.arvalid = state == AR; req.araddr = 32'h87ff_8000;
        req.arsize = 4; req.rready = state == R;
    end
    always_ff @(posedge clk) begin
        if (!rst_n) begin state <= AW; trips <= 0; errors <= 0; end
        else case (state)
            AW: if (stop) state <= STOPPED;
                else if (rsp.awready) state <= W;
            W: if (rsp.wready) state <= B;
            B: if (rsp.bvalid) begin
                if (rsp.bresp != AXI_OKAY) errors <= errors + 1;
                state <= AR;
            end
            AR: if (rsp.arready) state <= R;
            R: if (rsp.rvalid) begin
                if (rsp.rresp != AXI_OKAY || !rsp.rlast || rsp.rdata != pattern)
                    errors <= errors + 1;
                trips <= trips + 1;
                state <= AW;
            end
            default: ;
        endcase
    end
endmodule
