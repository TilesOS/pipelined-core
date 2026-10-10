`timescale 1ns/1ps
// Directed competing writer connected to the real fabric, rather than a
// synthetic reservation-clear pulse. Modes are selected by the C++ driver.
module cache_test_dma (
    input logic clk, rst_n,
    input logic [31:0] mode,
    input logic retire_valid,
    input logic [31:0] retire_pc,
    input logic atomic_lock,
    output axi128_pkg::axi_req_t req,
    input axi128_pkg::axi_rsp_t rsp,
    output logic done, was_blocked
);
    import axi128_pkg::*;
    typedef enum logic [2:0] {WAIT_TRIGGER, SEND_AW, DELAY_W, SEND_W, WAIT_B, DONE} state_t;
    state_t state;
    logic [5:0] delay_count;
    logic beat;
    always_comb begin
        req = '0;
        req.awvalid = state == SEND_AW;
        req.awaddr = mode == 6 ? 32'h8000_1000 : 32'h8780_0000;
        req.awlen = mode == 4 ? 1 : 0;
        req.awsize = 4;
        req.awid = 3;
        req.wvalid = state == SEND_W;
        req.wdata = mode == 2 ? 128'd9 << 32 : 128'd9;
        req.wstrb = mode == 2 ? 16'h00f0 : 16'h000f;
        req.wlast = mode != 4 || beat;
        req.bready = state == WAIT_B;
        done = state == DONE;
    end
    always_ff @(posedge clk) begin
        if (!rst_n) begin state <= WAIT_TRIGGER; beat <= 0; delay_count <= 0; was_blocked <= 0; end
        else begin
            if (req.awvalid && atomic_lock) begin
                was_blocked <= 1;
                if (rsp.awready) $fatal(1, "competing write admitted during atomic lock");
            end
            case (state)
                WAIT_TRIGGER: if (mode != 0 &&
                    ((mode == 3 && atomic_lock) ||
                     (mode == 5 && retire_valid && retire_pc == 32'h8000_0008) ||
                     (mode != 3 && mode != 5 && retire_valid && retire_pc == 32'h8000_000c)))
                    state <= SEND_AW;
                SEND_AW: if (rsp.awready) begin
                    delay_count <= mode == 5 ? 35 : 0;
                    state <= DELAY_W;
                end
                DELAY_W: if (delay_count == 0) state <= SEND_W;
                    else delay_count <= delay_count - 1;
                SEND_W: if (rsp.wready) begin
                    if (req.wlast) state <= WAIT_B;
                    else beat <= 1;
                end
                WAIT_B: if (rsp.bvalid) begin
                    if (rsp.bresp != (mode == 6 ? AXI_DECERR : AXI_OKAY)) $fatal(1, "DMA response mismatch");
                    state <= DONE;
                end
                default: ;
            endcase
        end
    end
endmodule
