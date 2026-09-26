`timescale 1ns/1ps
package axi128_pkg;
    // Restricted AXI4: 128-bit data, 32-bit addresses, one fixed ID per master.
    // LEN is AXI's beats-minus-one field; only INCR bursts are generated.
    typedef struct packed {
        logic        awvalid;
        logic [31:0] awaddr;
        logic [3:0]  awlen;
        logic [2:0]  awsize;
        logic [3:0]  awid;
        logic        wvalid;
        logic [127:0] wdata;
        logic [15:0] wstrb;
        logic        wlast;
        logic        bready;
        logic        arvalid;
        logic [31:0] araddr;
        logic [3:0]  arlen;
        logic [2:0]  arsize;
        logic [3:0]  arid;
        logic        rready;
    } axi_req_t;

    typedef struct packed {
        logic        awready;
        logic        wready;
        logic        bvalid;
        logic [1:0]  bresp;
        logic [3:0]  bid;
        logic        arready;
        logic        rvalid;
        logic [127:0] rdata;
        logic [1:0]  rresp;
        logic        rlast;
        logic [3:0]  rid;
    } axi_rsp_t;

    localparam logic [1:0] AXI_OKAY = 2'b00;
    localparam logic [1:0] AXI_SLVERR = 2'b10;
    localparam logic [1:0] AXI_DECERR = 2'b11;
endpackage
