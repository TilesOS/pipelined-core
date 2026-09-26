`timescale 1ns/1ps
module axi_fabric (
    input  logic clk,
    input  logic rst_n,
    input  axi128_pkg::axi_req_t m_req [4],
    output axi128_pkg::axi_rsp_t m_rsp [4],
    // Slave 0 is DDR; slave 1 is the ROM/MMIO peripheral adapter.
    output axi128_pkg::axi_req_t s_req [2],
    input  axi128_pkg::axi_rsp_t s_rsp [2],
    output logic [1:0] read_owner_probe,
    output logic [1:0] write_owner_probe,
    output logic [1:0] active_probe
);
    import axi128_pkg::*;

    typedef enum logic [1:0] {R_IDLE, R_DATA, R_ERROR} rstate_t;
    typedef enum logic [1:0] {W_IDLE, W_DATA, W_RESP, W_ERROR} wstate_t;
    rstate_t rstate;
    wstate_t wstate;
    logic [1:0] r_owner, w_owner, r_next, w_next;
    logic r_slave, w_slave;
    logic [3:0] w_remaining;
    logic [3:0] r_id, w_id;
    logic w_error;
    logic [1:0] r_pick, w_pick;
    logic r_found, w_found;
    logic [1:0] r_decode, w_decode;

    function automatic logic [1:0] decode(input logic [31:0] addr,
                                           input logic [3:0] len,
                                           input logic [2:0] size,
                                           input logic is_write);
        logic [32:0] last_byte;
        logic mapped;
        begin
            last_byte = {1'b0, addr} + (({29'b0, len} + 33'd1) << size) - 33'd1;
            mapped = (addr <= 32'h0000_ffff && last_byte <= 33'h0_0000_ffff && !is_write) ||
                     (addr >= 32'h0200_0000 && last_byte <= 33'h0_0200_ffff) ||
                     (addr >= 32'h0c00_0000 && last_byte <= 33'h0_0fff_ffff) ||
                     (addr >= 32'h1000_0000 && last_byte <= 33'h0_1000_0fff) ||
                     (addr >= 32'h1001_0000 && last_byte <= 33'h0_1001_0fff) ||
                     (addr >= 32'h1002_0000 && last_byte <= 33'h0_1002_0fff) ||
                     (addr >= 32'h1003_0000 && last_byte <= 33'h0_1003_0fff);
            if (size > 3'd4 || (addr & ((32'd1 << size) - 32'd1)) != 0 || last_byte[32] ||
                last_byte[31:12] != addr[31:12]) decode = 2'd2;
            else if (size == 3'd4 && addr >= 32'h8000_0000 &&
                     last_byte <= 33'h0_87ff_ffff)
                decode = 2'd0;
            else if (len == 0 && mapped) decode = 2'd1;
            else decode = 2'd2;
        end
    endfunction

    always_comb begin
        r_found = 1'b0;
        w_found = 1'b0;
        r_pick = '0;
        w_pick = '0;
        for (int offset = 0; offset < 4; offset++) begin
            if (!r_found && m_req[(int'(r_next) + offset) % 4].arvalid) begin
                r_found = 1'b1;
                r_pick = 2'((int'(r_next) + offset) % 4);
            end
            if (!w_found && m_req[(int'(w_next) + offset) % 4].awvalid) begin
                w_found = 1'b1;
                w_pick = 2'((int'(w_next) + offset) % 4);
            end
        end
        r_decode = decode(m_req[r_pick].araddr, m_req[r_pick].arlen,
                          m_req[r_pick].arsize, 1'b0);
        w_decode = decode(m_req[w_pick].awaddr, m_req[w_pick].awlen,
                          m_req[w_pick].awsize, 1'b1);
    end

    always_comb begin
        for (int i = 0; i < 4; i++) m_rsp[i] = '0;
        for (int i = 0; i < 2; i++) s_req[i] = '0;
        if (rstate == R_IDLE && r_found) begin
            if (r_decode == 2) m_rsp[r_pick].arready = 1'b1;
            else begin
                s_req[r_decode[0]].arvalid = m_req[r_pick].arvalid;
                s_req[r_decode[0]].araddr = m_req[r_pick].araddr;
                s_req[r_decode[0]].arlen = m_req[r_pick].arlen;
                s_req[r_decode[0]].arsize = m_req[r_pick].arsize;
                s_req[r_decode[0]].arid = {2'b00, r_pick};
                m_rsp[r_pick].arready = s_rsp[r_decode[0]].arready;
            end
        end else if (rstate == R_DATA) begin
            m_rsp[r_owner].rvalid = s_rsp[r_slave].rvalid;
            m_rsp[r_owner].rdata = s_rsp[r_slave].rdata;
            m_rsp[r_owner].rresp = s_rsp[r_slave].rresp;
            m_rsp[r_owner].rlast = s_rsp[r_slave].rlast;
            m_rsp[r_owner].rid = r_id;
            s_req[r_slave].rready = m_req[r_owner].rready;
        end else if (rstate == R_ERROR) begin
            m_rsp[r_owner].rvalid = 1'b1;
            m_rsp[r_owner].rresp = AXI_DECERR;
            m_rsp[r_owner].rlast = 1'b1;
            m_rsp[r_owner].rid = r_id;
        end

        if (wstate == W_IDLE && w_found) begin
            if (w_decode == 2) m_rsp[w_pick].awready = 1'b1;
            else begin
                s_req[w_decode[0]].awvalid = m_req[w_pick].awvalid;
                s_req[w_decode[0]].awaddr = m_req[w_pick].awaddr;
                s_req[w_decode[0]].awlen = m_req[w_pick].awlen;
                s_req[w_decode[0]].awsize = m_req[w_pick].awsize;
                s_req[w_decode[0]].awid = {2'b00, w_pick};
                m_rsp[w_pick].awready = s_rsp[w_decode[0]].awready;
            end
        end else if (wstate == W_DATA) begin
            s_req[w_slave].wvalid = m_req[w_owner].wvalid;
            s_req[w_slave].wdata = m_req[w_owner].wdata;
            s_req[w_slave].wstrb = m_req[w_owner].wstrb;
            s_req[w_slave].wlast = m_req[w_owner].wlast;
            m_rsp[w_owner].wready = s_rsp[w_slave].wready;
        end else if (wstate == W_ERROR) begin
            m_rsp[w_owner].wready = 1'b1;
        end else if (wstate == W_RESP) begin
            if (w_error) begin
                m_rsp[w_owner].bvalid = 1'b1;
                m_rsp[w_owner].bresp = AXI_DECERR;
            end else if (w_slave) begin
                m_rsp[w_owner].bvalid = s_rsp[1].bvalid;
                m_rsp[w_owner].bresp = s_rsp[1].bresp;
                s_req[1].bready = m_req[w_owner].bready;
            end else begin
                m_rsp[w_owner].bvalid = s_rsp[0].bvalid;
                m_rsp[w_owner].bresp = s_rsp[0].bresp;
                s_req[0].bready = m_req[w_owner].bready;
            end
            m_rsp[w_owner].bid = w_id;
        end
    end

    assign read_owner_probe = r_owner;
    assign write_owner_probe = w_owner;
    assign active_probe = {wstate != W_IDLE, rstate != R_IDLE};

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rstate <= R_IDLE;
            wstate <= W_IDLE;
            r_owner <= '0;
            w_owner <= '0;
            r_next <= '0;
            w_next <= '0;
            r_slave <= 1'b0;
            w_slave <= 1'b0;
            r_id <= '0;
            w_id <= '0;
            w_remaining <= '0;
            w_error <= 1'b0;
        end else begin
            case (rstate)
                R_IDLE: if (r_found && m_rsp[r_pick].arready) begin
                    r_owner <= r_pick;
                    r_id <= m_req[r_pick].arid;
                    if (r_decode == 2) rstate <= R_ERROR;
                    else begin
                        r_slave <= r_decode[0];
                        rstate <= R_DATA;
                    end
                end
                R_DATA: if (m_rsp[r_owner].rvalid && m_req[r_owner].rready &&
                            m_rsp[r_owner].rlast) begin
                    r_next <= r_owner + 2'd1;
                    rstate <= R_IDLE;
                end
                R_ERROR: if (m_req[r_owner].rready) begin
                    r_next <= r_owner + 2'd1;
                    rstate <= R_IDLE;
                end
                default: rstate <= R_IDLE;
            endcase
            case (wstate)
                W_IDLE: if (w_found && m_rsp[w_pick].awready) begin
                    w_owner <= w_pick;
                    w_id <= m_req[w_pick].awid;
                    w_remaining <= m_req[w_pick].awlen;
                    w_error <= (w_decode == 2);
                    if (w_decode == 2) wstate <= W_ERROR;
                    else begin
                        w_slave <= w_decode[0];
                        wstate <= W_DATA;
                    end
                end
                W_DATA: if (m_req[w_owner].wvalid && m_rsp[w_owner].wready) begin
                    if (w_remaining == 0) wstate <= W_RESP;
                    else w_remaining <= w_remaining - 4'd1;
                end
                W_ERROR: if (m_req[w_owner].wvalid) begin
                    if (w_remaining == 0) wstate <= W_RESP;
                    else w_remaining <= w_remaining - 4'd1;
                end
                W_RESP: if (m_rsp[w_owner].bvalid && m_req[w_owner].bready) begin
                    w_next <= w_owner + 2'd1;
                    wstate <= W_IDLE;
                end
                default: wstate <= W_IDLE;
            endcase
        end
    end
endmodule
