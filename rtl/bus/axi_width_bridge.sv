`timescale 1ns/1ps
// One CPU-side byte/halfword/word request at a time. The CPU pipeline must
// hold req_valid until req_ready, then wait for rsp_valid before issuing again.
module axi_width_bridge #(
    parameter logic [3:0] MASTER_ID = 4'd0
) (
    input  logic clk,
    input  logic rst_n,
    input  logic req_valid,
    output logic req_ready,
    input  logic req_write,
    input  logic req_narrow,
    input  logic [31:0] req_addr,
    input  logic [1:0] req_size,
    input  logic [31:0] req_wdata,
    input  logic [3:0] req_wstrb,
    output logic rsp_valid,
    input  logic rsp_ready,
    output logic [31:0] rsp_rdata,
    output logic [1:0] rsp_resp,
    output axi128_pkg::axi_req_t axi_req,
    input  axi128_pkg::axi_rsp_t axi_rsp
);
    import axi128_pkg::*;
    typedef enum logic [2:0] {IDLE, SEND_READ, WAIT_READ,
                              SEND_WRITE, WAIT_WRITE, RESPONSE} state_t;
    state_t state;
    logic [31:0] held_addr, held_wdata;
    logic [1:0] held_size;
    logic held_narrow;
    logic [3:0] held_strb;
    logic aw_done, w_done;
    logic [31:0] result_data;
    logic [1:0] result_resp;
    logic bad_request;

    assign bad_request = ((req_size == 2'd1) && req_addr[0]) ||
                         ((req_size == 2'd2) && |req_addr[1:0]) ||
                         (req_size == 2'd3) ||
                         (({1'b0, req_addr[3:0]} + (5'd1 << req_size)) > 5'd16);
    assign req_ready = state == IDLE;
    assign rsp_valid = state == RESPONSE;
    assign rsp_rdata = result_data;
    assign rsp_resp = result_resp;

    always_comb begin
        axi_req = '0;
        axi_req.awaddr = held_narrow ? held_addr : {held_addr[31:4], 4'b0};
        axi_req.araddr = held_narrow ? held_addr : {held_addr[31:4], 4'b0};
        axi_req.awsize = held_narrow ? {1'b0, held_size} : 3'd4;
        axi_req.arsize = held_narrow ? {1'b0, held_size} : 3'd4;
        axi_req.awid = MASTER_ID;
        axi_req.arid = MASTER_ID;
        axi_req.wdata = {96'b0, held_wdata} << (8 * held_addr[3:0]);
        axi_req.wstrb = {12'b0, held_strb} << held_addr[3:0];
        axi_req.wlast = 1'b1;
        axi_req.arvalid = state == SEND_READ;
        axi_req.rready = state == WAIT_READ;
        axi_req.awvalid = state == SEND_WRITE && !aw_done;
        axi_req.wvalid = state == SEND_WRITE && !w_done;
        axi_req.bready = state == WAIT_WRITE;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            held_addr <= '0;
            held_wdata <= '0;
            held_size <= '0;
            held_narrow <= 1'b0;
            held_strb <= '0;
            aw_done <= 1'b0;
            w_done <= 1'b0;
            result_data <= '0;
            result_resp <= AXI_OKAY;
        end else begin
            case (state)
                IDLE: if (req_valid) begin
                    held_addr <= req_addr;
                    held_wdata <= req_wdata;
                    held_size <= req_size;
                    held_narrow <= req_narrow;
                    held_strb <= req_wstrb;
                    result_data <= '0;
                    result_resp <= AXI_OKAY;
                    aw_done <= 1'b0;
                    w_done <= 1'b0;
                    if (bad_request) begin
                        result_resp <= AXI_SLVERR;
                        state <= RESPONSE;
                    end else if (req_write) state <= SEND_WRITE;
                    else state <= SEND_READ;
                end
                SEND_READ: if (axi_rsp.arready) state <= WAIT_READ;
                WAIT_READ: if (axi_rsp.rvalid) begin
                    result_data <= 32'(axi_rsp.rdata >> (8 * held_addr[3:0]));
                    result_resp <= axi_rsp.rresp;
                    state <= RESPONSE;
                end
                SEND_WRITE: begin
                    if (axi_rsp.awready && !aw_done) aw_done <= 1'b1;
                    if (axi_rsp.wready && !w_done) w_done <= 1'b1;
                    if ((aw_done || axi_rsp.awready) &&
                        (w_done || axi_rsp.wready)) state <= WAIT_WRITE;
                end
                WAIT_WRITE: if (axi_rsp.bvalid) begin
                    result_resp <= axi_rsp.bresp;
                    state <= RESPONSE;
                end
                RESPONSE: if (rsp_ready) state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end
endmodule
