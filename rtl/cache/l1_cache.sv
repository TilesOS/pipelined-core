`timescale 1ns/1ps
// Blocking, physically indexed/tagged 8 KiB, two ways, 128 sets, 32-byte lines.
// CPU data/strobes are relative to req_addr (as in axi_width_bridge).
// Data/tag reads are clocked. Data RAM has no reset; valid bits gate its use.
module l1_cache #(
    parameter bit READ_ONLY = 0,
    parameter logic [3:0] MASTER_ID = 1
) (
    input logic clk, rst_n,
    input logic req_valid,
    output logic req_ready,
    input logic req_write,
    input logic [31:0] req_addr, req_wdata,
    input logic [1:0] req_size,
    input logic [3:0] req_wstrb,
    output logic rsp_valid,
    input logic rsp_ready,
    output logic [31:0] rsp_rdata,
    output logic [1:0] rsp_resp,
    // clean writes every dirty line back, retaining valid data. Invalidate
    // follows a completed clean on the D-cache; the I-cache has no dirty data.
    input logic clean_valid, invalidate_valid,
    output logic maintenance_done,
    output logic maintenance_fault,
    output axi128_pkg::axi_req_t axi_req,
    input axi128_pkg::axi_rsp_t axi_rsp,
    output logic [31:0] miss_count, writeback_count, bypass_count
);
    import axi128_pkg::*;
    import physical_memory_pkg::*;
    typedef enum logic [3:0] {IDLE, LOOKUP_READ, LOOKUP, REFILL_AR, REFILL_R,
        WB_AW, WB_W, WB_B, RESPONSE, BYPASS_REQ, BYPASS_RSP,
        SCAN, SCAN_READ, MAINT_DONE} state_t;
    (* mark_debug = "true" *) state_t state;
    (* ram_style = "block" *) logic [255:0] data0 [128], data1 [128];
    logic [19:0] tags0 [128], tags1 [128];
    logic [127:0] valid0, valid1, dirty0, dirty1, lru;
    logic [255:0] q0, q1, writeback_line, refill_line;
    logic [19:0] qt0, qt1;
    logic hit0, hit1, victim;
    logic [31:0] addr, wdata, writeback_addr, result;
    logic [1:0] size, response;
    logic [3:0] strb;
    logic write_request, beat, refill_error, cleaning, invalidating;
    logic [7:0] scan_index;
    logic [6:0] set_index;
    logic bridge_ready, bridge_valid;
    logic [31:0] bridge_data;
    logic [1:0] bridge_resp;
    axi_req_t bridge_req;
    axi_rsp_t bridge_rsp;
    logic [255:0] hit_line, store_line;
    logic [6:0] ram_read_index;
    logic ram_read_enable, ram_store, ram_refill, ram_write_way;
    logic [255:0] ram_write_data;

    assign set_index = addr[11:5];
    assign hit0 = valid0[set_index] && qt0 == addr[31:12];
    assign hit1 = valid1[set_index] && qt1 == addr[31:12];
    assign hit_line = hit1 ? q1 : q0;
    assign req_ready = state == IDLE && !clean_valid && !invalidate_valid;
    assign rsp_valid = state == RESPONSE;
    assign rsp_rdata = result;
    assign rsp_resp = response;
    assign maintenance_done = state == MAINT_DONE;

    // One synchronous read port per way serves lookup and maintenance. The
    // shared output has no reset; valid bits and the FSM gate every use.
    // Reading the arrays separately into q and writeback_line described two
    // read ports and prevented mapping this wide line store to block RAM.
    assign ram_read_index = state == SCAN ? scan_index[6:0] : set_index;
    assign ram_read_enable = state == LOOKUP_READ || state == SCAN;
    assign ram_store = state == LOOKUP && (hit0 || hit1) && write_request && !READ_ONLY;
    assign ram_refill = state == REFILL_R && axi_rsp.rvalid && beat &&
        axi_rsp.rlast && !refill_error && axi_rsp.rresp == AXI_OKAY;
    assign ram_write_way = ram_store ? hit1 : victim;
    assign ram_write_data = ram_store ? store_line : {axi_rsp.rdata, refill_line[127:0]};
    always_ff @(posedge clk) begin
        if (rst_n && ram_read_enable) begin
            q0 <= data0[ram_read_index]; q1 <= data1[ram_read_index];
            qt0 <= tags0[ram_read_index]; qt1 <= tags1[ram_read_index];
        end
        if (rst_n && (ram_store || ram_refill)) begin
            if (ram_write_way) data1[set_index] <= ram_write_data;
            else data0[set_index] <= ram_write_data;
        end
        if (rst_n && ram_refill) begin
            if (victim) tags1[set_index] <= addr[31:12];
            else tags0[set_index] <= addr[31:12];
        end
    end

    axi_width_bridge #(.MASTER_ID(MASTER_ID)) bypass (
        .clk(clk), .rst_n(rst_n), .req_valid(state == BYPASS_REQ),
        .req_ready(bridge_ready), .req_write(write_request),
        .req_narrow(!ddr(addr)), .req_addr(addr), .req_size(size),
        .req_wdata(wdata), .req_wstrb(strb), .rsp_valid(bridge_valid),
        .rsp_ready(state == BYPASS_RSP), .rsp_rdata(bridge_data),
        .rsp_resp(bridge_resp), .axi_req(bridge_req), .axi_rsp(bridge_rsp)
    );
    always_comb begin
        store_line = hit_line;
        for (int lane = 0; lane < 4; lane++)
            if (strb[lane]) store_line[8*(int'(addr[4:0])+lane) +: 8] = wdata[8*lane +: 8];
    end
    always_comb begin
        axi_req = '0;
        bridge_rsp = '0;
        if (state inside {BYPASS_REQ, BYPASS_RSP}) begin
            axi_req = bridge_req;
            bridge_rsp = axi_rsp;
        end else begin
            axi_req.arvalid = state == REFILL_AR;
            axi_req.araddr = {addr[31:5], 5'b0};
            axi_req.arlen = 1;
            axi_req.arsize = 4;
            axi_req.arid = MASTER_ID;
            axi_req.rready = state == REFILL_R;
            axi_req.awvalid = state == WB_AW;
            axi_req.awaddr = writeback_addr;
            axi_req.awlen = 1;
            axi_req.awsize = 4;
            axi_req.awid = MASTER_ID;
            axi_req.wvalid = state == WB_W;
            axi_req.wdata = beat ? writeback_line[255:128] : writeback_line[127:0];
            axi_req.wstrb = '1;
            axi_req.wlast = beat;
            axi_req.bready = state == WB_B;
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE;
            valid0 <= '0; valid1 <= '0;
            dirty0 <= '0; dirty1 <= '0; lru <= '0;
            addr <= 0; wdata <= 0; size <= 0; strb <= 0;
            write_request <= 0; victim <= 0; beat <= 0;
            writeback_addr <= 0; writeback_line <= 0; refill_line <= 0;
            result <= 0; response <= AXI_OKAY; refill_error <= 0;
            cleaning <= 0; invalidating <= 0; scan_index <= 0;
            maintenance_fault <= 0;
            miss_count <= 0; writeback_count <= 0; bypass_count <= 0;
        end else case (state)
            IDLE: begin
                if (clean_valid || invalidate_valid) begin
                    cleaning <= 1;
                    invalidating <= invalidate_valid;
                    maintenance_fault <= 0;
                    scan_index <= 0;
                    state <= SCAN;
                end else if (req_valid) begin
                    addr <= req_addr; wdata <= req_wdata;
                    size <= req_size; strb <= req_wstrb;
                    write_request <= req_write;
                    result <= 0; response <= AXI_OKAY;
                    cleaning <= 0;
                    if (!accessible(req_addr, req_write) ||
                        (READ_ONLY && (req_write || !executable(req_addr))) ||
                        req_size == 3 || (req_size == 1 && req_addr[0]) ||
                        (req_size == 2 && |req_addr[1:0])) begin
                        response <= AXI_DECERR;
                        state <= RESPONSE;
                    end else if (!cacheable(req_addr)) begin
                        bypass_count <= bypass_count + 1;
                        state <= BYPASS_REQ;
                    end else state <= LOOKUP_READ;
                end
            end
            LOOKUP_READ: begin
                state <= LOOKUP;
            end
            LOOKUP: begin
                if (hit0 || hit1) begin
                    result <= 32'(hit_line >> (8 * addr[4:0]));
                    lru[set_index] <= !hit1;
                    if (write_request && !READ_ONLY) begin
                        if (hit1) dirty1[set_index] <= 1;
                        else dirty0[set_index] <= 1;
                    end
                    state <= RESPONSE;
                end else begin
                    miss_count <= miss_count + 1;
                    victim <= !valid0[set_index] ? 1'b0 : !valid1[set_index] ? 1'b1 : lru[set_index];
                    beat <= 0; refill_error <= 0;
                    if (valid0[set_index] && valid1[set_index] &&
                        (lru[set_index] ? dirty1[set_index] : dirty0[set_index])) begin
                        writeback_line <= lru[set_index] ? q1 : q0;
                        writeback_addr <= {lru[set_index] ? qt1 : qt0, set_index, 5'b0};
                        state <= WB_AW;
                    end else state <= REFILL_AR;
                end
            end
            WB_AW: if (axi_rsp.awready) begin beat <= 0; state <= WB_W; end
            WB_W: if (axi_rsp.wready) begin
                if (beat) state <= WB_B;
                else beat <= 1;
            end
            WB_B: if (axi_rsp.bvalid) begin
                writeback_count <= writeback_count + 1;
                if (axi_rsp.bresp != AXI_OKAY) begin
                    // Retain the dirty victim on failure so data can be retried.
                    if (cleaning) begin maintenance_fault <= 1; state <= MAINT_DONE; end
                    else begin response <= axi_rsp.bresp; state <= RESPONSE; end
                end else begin
                    if (cleaning) begin
                        if (scan_index[7]) dirty1[scan_index[6:0]] <= 0;
                        else dirty0[scan_index[6:0]] <= 0;
                        if (scan_index == 255) state <= MAINT_DONE;
                        else begin scan_index <= scan_index + 1; state <= SCAN; end
                    end else begin
                        if (victim) begin valid1[set_index] <= 0; dirty1[set_index] <= 0; end
                        else begin valid0[set_index] <= 0; dirty0[set_index] <= 0; end
                        beat <= 0; refill_error <= 0;
                        state <= REFILL_AR;
                    end
                end
            end
            REFILL_AR: if (axi_rsp.arready) begin beat <= 0; state <= REFILL_R; end
            REFILL_R: if (axi_rsp.rvalid) begin
                refill_error <= refill_error || axi_rsp.rresp != AXI_OKAY || axi_rsp.rlast != beat;
                if (!beat) refill_line[127:0] <= axi_rsp.rdata;
                if (beat || axi_rsp.rlast) begin
                    if (refill_error || axi_rsp.rresp != AXI_OKAY || !beat || !axi_rsp.rlast) begin
                        response <= AXI_SLVERR;
                        state <= RESPONSE;
                    end else begin
                        if (victim) begin
                            valid1[set_index] <= 1; dirty1[set_index] <= 0;
                        end else begin
                            valid0[set_index] <= 1; dirty0[set_index] <= 0;
                        end
                        state <= LOOKUP_READ;
                    end
                end else beat <= 1;
            end
            RESPONSE: if (rsp_ready) state <= IDLE;
            BYPASS_REQ: if (bridge_ready) state <= BYPASS_RSP;
            BYPASS_RSP: if (bridge_valid) begin
                result <= bridge_data; response <= bridge_resp; state <= RESPONSE;
            end
            SCAN: begin
                if (!READ_ONLY && (scan_index[7] ? dirty1[scan_index[6:0]] : dirty0[scan_index[6:0]]))
                    state <= SCAN_READ;
                else if (scan_index == 255) state <= MAINT_DONE;
                else scan_index <= scan_index + 1;
            end
            SCAN_READ: begin
                writeback_line <= scan_index[7] ? q1 : q0;
                writeback_addr <= {scan_index[7] ? qt1 : qt0, scan_index[6:0], 5'b0};
                state <= WB_AW;
            end
            MAINT_DONE: begin
                if (invalidating && !maintenance_fault) begin valid0 <= 0; valid1 <= 0; end
                if (!clean_valid && !invalidate_valid) state <= IDLE;
            end
            default: state <= IDLE;
        endcase
    end
endmodule
