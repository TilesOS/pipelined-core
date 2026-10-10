`timescale 1ns/1ps
module cache_test_memory #(
    parameter int BYTES = 262144,
    parameter bit LOAD_IMAGE = 0
) (
    input logic clk,
    input logic rst_n,
    input axi128_pkg::axi_req_t req,
    output axi128_pkg::axi_rsp_t rsp
);
    import axi128_pkg::*;
    logic [7:0] mem [BYTES];
    logic [15:0] noise;
    logic [15:0] noise_seed = 16'hace1;
    logic w_active, b_pending, r_active, b_offer, r_offer;
    logic [31:0] w_addr, r_addr;
    logic [3:0] w_left, r_left, w_id, r_id;
    logic [127:0] read_data;
    string image_path;
    logic [31:0] fail_read_addr = 32'hffff_ffff, fail_write_addr = 32'hffff_ffff;
    logic [31:0] w_base, r_base;
    function automatic int offset(input logic [31:0] address);
        if (BYTES == 65536) return int'(address[15:0]);
        if (address >= 32'h8780_0000) return 131072 + int'(address[15:0]);
        if (address < 32'h8000_0000) return 196608 + int'(address[15:0]);
        return int'(address[16:0]);
    endfunction

    int r_offset, w_offset;
    assign r_offset = offset(r_addr);
    assign w_offset = offset(w_addr);
    initial begin
        void'($value$plusargs("seed=%d", noise_seed));
        if (noise_seed == 0) $fatal(1, "LFSR seed must be nonzero");
        for (int i = 0; i < BYTES; i++) mem[i] = LOAD_IMAGE ? 8'b0 : 8'(i ^ 32'h5a);
        if (LOAD_IMAGE) begin
            if (!$value$plusargs("image=%s", image_path)) $fatal(1, "missing +image hex file");
            $readmemh(image_path, mem);
        end
        void'($value$plusargs("fail_read_addr=%h", fail_read_addr));
        void'($value$plusargs("fail_write_addr=%h", fail_write_addr));
    end
    always_comb begin
        read_data = '0;
        for (int i = 0; i < 16; i++)
            read_data[i*8 +: 8] = mem[(r_offset + i) % BYTES];
        rsp = '0;
        rsp.awready = !w_active && !b_pending && noise[0];
        rsp.wready = w_active && noise[1];
        rsp.bvalid = b_pending && b_offer;
        rsp.bid = w_id;
        rsp.bresp = w_base == fail_write_addr ? AXI_SLVERR : AXI_OKAY;
        rsp.arready = !r_active && noise[3];
        rsp.rvalid = r_active && r_offer;
        rsp.rdata = read_data;
        rsp.rresp = r_base == fail_read_addr ? AXI_SLVERR : AXI_OKAY;
        rsp.rlast = r_left == 0;
        rsp.rid = r_id;
    end
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            noise <= noise_seed;
            w_active <= 1'b0;
            b_pending <= 1'b0;
            r_active <= 1'b0;
            b_offer <= 1'b0;
            r_offer <= 1'b0;
            w_addr <= '0; w_base <= 0; r_base <= 0;
            r_addr <= '0;
            w_left <= '0;
            r_left <= '0;
            w_id <= '0;
            r_id <= '0;
        end else begin
            noise <= {noise[14:0], noise[15] ^ noise[13] ^ noise[12] ^ noise[10]};
            if (req.awvalid && rsp.awready) begin
                w_active <= 1'b1;
                w_addr <= {req.awaddr[31:4], 4'b0};
                w_base <= req.awaddr;
                w_left <= req.awlen;
                w_id <= req.awid;
            end
            if (req.wvalid && rsp.wready) begin
                for (int i = 0; i < 16; i++)
                    if (req.wstrb[i]) mem[(w_offset + i) % BYTES] <= req.wdata[i*8 +: 8];
                w_addr <= w_addr + 32'd16;
                if ((w_left == 0) != req.wlast) $fatal(1, "bad WLAST");
                if (w_left == 0) begin
                    w_active <= 1'b0;
                    b_pending <= 1'b1;
                    b_offer <= 1'b0;
                end else w_left <= w_left - 4'd1;
            end
            if (b_pending && !b_offer && noise[2]) b_offer <= 1'b1;
            if (rsp.bvalid && req.bready) begin
                b_pending <= 1'b0;
                b_offer <= 1'b0;
            end
            if (req.arvalid && rsp.arready) begin
                r_active <= 1'b1;
                r_addr <= {req.araddr[31:4], 4'b0};
                r_base <= req.araddr;
                r_left <= req.arlen;
                r_id <= req.arid;
                r_offer <= 1'b0;
            end
            if (r_active && !r_offer && noise[4]) r_offer <= 1'b1;
            if (rsp.rvalid && req.rready) begin
                r_addr <= r_addr + 32'd16;
                r_offer <= 1'b0;
                if (r_left == 0) r_active <= 1'b0;
                else r_left <= r_left - 4'd1;
            end
        end
    end
endmodule
