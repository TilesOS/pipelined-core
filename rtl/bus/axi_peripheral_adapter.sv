`timescale 1ns/1ps
// Single-beat AXI to a byte-addressed device request/response port.
// The device receives the exact byte address and size, so register reads
// cause only one device operation. The port serializes reads and writes.
module axi_peripheral_adapter (
    input logic clk,
    input logic rst_n,
    input axi128_pkg::axi_req_t axi_req,
    output axi128_pkg::axi_rsp_t axi_rsp,
    output logic bus_req_valid,
    input logic bus_req_ready,
    output logic bus_req_write,
    output logic [31:0] bus_req_addr,
    output logic [1:0] bus_req_size,
    output logic [31:0] bus_req_wdata,
    output logic [3:0] bus_req_wstrb,
    input logic bus_rsp_valid,
    output logic bus_rsp_ready,
    input logic [31:0] bus_rsp_rdata,
    input logic bus_rsp_decode_error,
    input logic bus_rsp_error
);
    import axi128_pkg::*;
    typedef enum logic [2:0] {IDLE, W_CAPTURE, W_REQUEST, W_WAIT,
                              W_RESPONSE, R_REQUEST, R_WAIT, R_RESPONSE} state_t;
    state_t state;
    logic [31:0] addr, wdata, rdata;
    logic [1:0] size, response;
    logic [3:0] id, wstrb;
    logic [3:0] write_remaining;
    logic invalid;
    logic [15:0] allowed_strobes;
    assign allowed_strobes = (16'hffff >> (16 - (1 << size))) << addr[3:0];

    always_comb begin
        axi_rsp = '0;
        // Read priority if both address channels arrive in the same cycle.
        axi_rsp.arready = state == IDLE;
        axi_rsp.awready = state == IDLE && !axi_req.arvalid;
        axi_rsp.wready = state == W_CAPTURE;
        axi_rsp.bvalid = state == W_RESPONSE;
        axi_rsp.bresp = response;
        axi_rsp.bid = id;
        axi_rsp.rvalid = state == R_RESPONSE;
        axi_rsp.rresp = response;
        axi_rsp.rid = id;
        axi_rsp.rlast = state == R_RESPONSE;
        axi_rsp.rdata = {96'b0, rdata} << (8 * addr[3:0]);
        bus_req_valid = state == W_REQUEST || state == R_REQUEST;
        bus_req_write = state == W_REQUEST;
        bus_req_addr = addr;
        bus_req_size = size;
        bus_req_wdata = wdata;
        bus_req_wstrb = wstrb;
        bus_rsp_ready = state == W_WAIT || state == R_WAIT;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            addr <= '0;
            size <= '0;
            id <= '0;
            wdata <= '0;
            wstrb <= '0;
            write_remaining <= '0;
            rdata <= '0;
            response <= AXI_OKAY;
            invalid <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    if (axi_req.arvalid) begin
                        addr <= axi_req.araddr;
                        size <= axi_req.arsize[1:0];
                        id <= axi_req.arid;
                        rdata <= '0;
                        response <= AXI_OKAY;
                        if (axi_req.arlen != 0 || axi_req.arsize > 3'd2 ||
                            (axi_req.araddr & ((32'd1 << axi_req.arsize)-1)) != 0) begin
                            response <= AXI_SLVERR;
                            state <= R_RESPONSE;
                        end else state <= R_REQUEST;
                    end else if (axi_req.awvalid) begin
                        addr <= axi_req.awaddr;
                        size <= axi_req.awsize[1:0];
                        id <= axi_req.awid;
                        write_remaining <= axi_req.awlen;
                        invalid <= axi_req.awlen != 0 || axi_req.awsize > 3'd2 ||
                            (axi_req.awaddr & ((32'd1 << axi_req.awsize)-1)) != 0;
                        response <= AXI_OKAY;
                        state <= W_CAPTURE;
                    end
                end
                W_CAPTURE: if (axi_req.wvalid) begin
                    wdata <= 32'(axi_req.wdata >> (8 * addr[3:0]));
                    wstrb <= 4'(axi_req.wstrb >> addr[3:0]);
                    if (write_remaining != 0) begin
                        write_remaining <= write_remaining - 4'd1;
                    end else if (invalid || !axi_req.wlast || (axi_req.wstrb & ~allowed_strobes) != 0) begin
                        response <= AXI_SLVERR;
                        state <= W_RESPONSE;
                    end else state <= W_REQUEST;
                end
                W_REQUEST: if (bus_req_ready) state <= W_WAIT;
                W_WAIT: if (bus_rsp_valid) begin
                    response <= bus_rsp_decode_error ? AXI_DECERR : bus_rsp_error ? AXI_SLVERR : AXI_OKAY;
                    state <= W_RESPONSE;
                end
                W_RESPONSE: if (axi_req.bready) state <= IDLE;
                R_REQUEST: if (bus_req_ready) state <= R_WAIT;
                R_WAIT: if (bus_rsp_valid) begin
                    rdata <= bus_rsp_rdata;
                    response <= bus_rsp_decode_error ? AXI_DECERR : bus_rsp_error ? AXI_SLVERR : AXI_OKAY;
                    state <= R_RESPONSE;
                end
                R_RESPONSE: if (axi_req.rready) state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end
endmodule
