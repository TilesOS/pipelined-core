`timescale 1ns/1ps
module axi_cdc (
    input  logic core_clk,
    input  logic mig_clk,
    input  logic rst_n,
    input  axi128_pkg::axi_req_t core_req,
    output axi128_pkg::axi_rsp_t core_rsp,
    output axi128_pkg::axi_req_t mig_req,
    input  axi128_pkg::axi_rsp_t mig_rsp,
    // Write-side levels for AW, W, AR; read-side levels for B, R.
    output logic [2:0] aw_level,
    output logic [2:0] w_level,
    output logic [2:0] ar_level,
    output logic [2:0] b_level,
    output logic [2:0] r_level
);
    import axi128_pkg::*;
    typedef struct packed {
        logic [31:0] addr;
        logic [3:0] len;
        logic [2:0] size;
        logic [3:0] id;
    } command_t;
    typedef struct packed {
        logic [127:0] data;
        logic [15:0] strb;
        logic last;
    } write_t;
    typedef struct packed {
        logic [1:0] resp;
        logic [3:0] id;
    } response_t;
    typedef struct packed {
        logic [127:0] data;
        logic [1:0] resp;
        logic last;
        logic [3:0] id;
    } read_t;
    command_t aw_in, aw_out, ar_in, ar_out;
    write_t w_in, w_out;
    response_t b_in, b_out;
    read_t r_in, r_out;
    logic aw_in_ready, aw_out_valid, w_in_ready, w_out_valid;
    logic ar_in_ready, ar_out_valid, b_in_ready, b_out_valid;
    logic r_in_ready, r_out_valid;

    assign aw_in = '{core_req.awaddr, core_req.awlen, core_req.awsize, core_req.awid};
    assign ar_in = '{core_req.araddr, core_req.arlen, core_req.arsize, core_req.arid};
    assign w_in = '{core_req.wdata, core_req.wstrb, core_req.wlast};
    assign b_in = '{mig_rsp.bresp, mig_rsp.bid};
    assign r_in = '{mig_rsp.rdata, mig_rsp.rresp, mig_rsp.rlast, mig_rsp.rid};

    async_fifo #(.WIDTH($bits(command_t))) aw_fifo (
        .wr_clk(core_clk), .rd_clk(mig_clk), .rst_n(rst_n),
        .in_valid(core_req.awvalid), .in_ready(aw_in_ready), .in_data(aw_in),
        .out_valid(aw_out_valid), .out_ready(mig_rsp.awready), .out_data(aw_out),
        .wr_level(aw_level), .rd_level()
    );
    async_fifo #(.WIDTH($bits(write_t))) w_fifo (
        .wr_clk(core_clk), .rd_clk(mig_clk), .rst_n(rst_n),
        .in_valid(core_req.wvalid), .in_ready(w_in_ready), .in_data(w_in),
        .out_valid(w_out_valid), .out_ready(mig_rsp.wready), .out_data(w_out),
        .wr_level(w_level), .rd_level()
    );
    async_fifo #(.WIDTH($bits(command_t))) ar_fifo (
        .wr_clk(core_clk), .rd_clk(mig_clk), .rst_n(rst_n),
        .in_valid(core_req.arvalid), .in_ready(ar_in_ready), .in_data(ar_in),
        .out_valid(ar_out_valid), .out_ready(mig_rsp.arready), .out_data(ar_out),
        .wr_level(ar_level), .rd_level()
    );
    async_fifo #(.WIDTH($bits(response_t))) b_fifo (
        .wr_clk(mig_clk), .rd_clk(core_clk), .rst_n(rst_n),
        .in_valid(mig_rsp.bvalid), .in_ready(b_in_ready), .in_data(b_in),
        .out_valid(b_out_valid), .out_ready(core_req.bready), .out_data(b_out),
        .wr_level(), .rd_level(b_level)
    );
    async_fifo #(.WIDTH($bits(read_t))) r_fifo (
        .wr_clk(mig_clk), .rd_clk(core_clk), .rst_n(rst_n),
        .in_valid(mig_rsp.rvalid), .in_ready(r_in_ready), .in_data(r_in),
        .out_valid(r_out_valid), .out_ready(core_req.rready), .out_data(r_out),
        .wr_level(), .rd_level(r_level)
    );

    always_comb begin
        core_rsp = '0;
        core_rsp.awready = aw_in_ready;
        core_rsp.wready = w_in_ready;
        core_rsp.arready = ar_in_ready;
        core_rsp.bvalid = b_out_valid;
        core_rsp.bresp = b_out.resp;
        core_rsp.bid = b_out.id;
        core_rsp.rvalid = r_out_valid;
        core_rsp.rdata = r_out.data;
        core_rsp.rresp = r_out.resp;
        core_rsp.rlast = r_out.last;
        core_rsp.rid = r_out.id;
        mig_req = '0;
        mig_req.awvalid = aw_out_valid;
        mig_req.awaddr = aw_out.addr;
        mig_req.awlen = aw_out.len;
        mig_req.awsize = aw_out.size;
        mig_req.awid = aw_out.id;
        mig_req.wvalid = w_out_valid;
        mig_req.wdata = w_out.data;
        mig_req.wstrb = w_out.strb;
        mig_req.wlast = w_out.last;
        mig_req.arvalid = ar_out_valid;
        mig_req.araddr = ar_out.addr;
        mig_req.arlen = ar_out.len;
        mig_req.arsize = ar_out.size;
        mig_req.arid = ar_out.id;
        mig_req.bready = b_in_ready;
        mig_req.rready = r_in_ready;
    end
endmodule
