`timescale 1ns/1ps
// Board-test image ROM, copied to DDR and read back before releasing the CPU.
// A calibration/reset interruption restarts the entire copy with cold caches.
module checkpoint10_image_loader #(
    parameter integer IMAGE_WORDS = 1,
    parameter integer ROM_WORDS = IMAGE_WORDS,
    parameter integer FIRMWARE_WORDS = ROM_WORDS,
    parameter integer PAYLOAD_WORD = FIRMWARE_WORDS,
    parameter IMAGE_FILE = "checkpoint10_image.mem",
    parameter integer TIMEOUT_CYCLES = 50_000_000
) (
    input logic clk, rst_n,
    output axi128_pkg::axi_req_t req,
    input axi128_pkg::axi_rsp_t rsp,
    output logic complete, error,
    output logic [31:0] progress
);
    import axi128_pkg::*;
    localparam integer INDEX_BITS = IMAGE_WORDS > 1 ? $clog2(IMAGE_WORDS) : 1;
    localparam integer ROM_INDEX_BITS = ROM_WORDS > 1 ? $clog2(ROM_WORDS) : 1;
    // Store firmware followed by payload; generate the reserved DDR gap as
    // zeroes instead of consuming block RAM for its address space.
    (* rom_style = "block" *) logic [127:0] image [0:ROM_WORDS-1];
    logic [INDEX_BITS-1:0] index;
    logic [ROM_INDEX_BITS-1:0] rom_index;
    logic [127:0] rom_word, image_word;
    logic gap_word;
    logic aw_pending, w_pending;
    logic [$clog2(TIMEOUT_CYCLES+1)-1:0] watchdog;
    typedef enum logic [2:0] {FETCH, WRITE, RESPONSE, READ, VERIFY, FINISHED, FAILED} state_t;
    state_t state;
    initial begin
        if (IMAGE_WORDS < 1 || IMAGE_WORDS > 7864320)
            $fatal(1, "image must fit cached DDR");
        if (FIRMWARE_WORDS < 1 || FIRMWARE_WORDS > PAYLOAD_WORD ||
            PAYLOAD_WORD > IMAGE_WORDS || ROM_WORDS != FIRMWARE_WORDS + IMAGE_WORDS - PAYLOAD_WORD)
            $fatal(1, "invalid compact ROM layout");
        $readmemh(IMAGE_FILE, image);
    end
    always_comb begin
        rom_index = '0;
        if (32'(index) < FIRMWARE_WORDS) rom_index = ROM_INDEX_BITS'(index);
        else if (32'(index) >= PAYLOAD_WORD)
            rom_index = ROM_INDEX_BITS'(32'(index) - PAYLOAD_WORD + FIRMWARE_WORDS);
    end
    // Synchronous ROM output permits BRAM inference; no ROM/output reset.
    always_ff @(posedge clk) begin
        rom_word <= image[rom_index];
        gap_word <= 32'(index) >= FIRMWARE_WORDS && 32'(index) < PAYLOAD_WORD;
    end
    assign image_word = gap_word ? 128'b0 : rom_word;
    assign complete = state == FINISHED;
    assign error = state == FAILED;
    always_comb begin
        req = '0;
        req.awaddr = 32'h80000000 + (32'(index) << 4);
        req.araddr = req.awaddr;
        req.awsize = 4;
        req.arsize = 4;
        req.awid = 2;
        req.arid = 2;
        req.wdata = image_word;
        req.wstrb = '1;
        req.wlast = 1;
        req.awvalid = state == WRITE && aw_pending;
        req.wvalid = state == WRITE && w_pending;
        req.bready = state == RESPONSE;
        req.arvalid = state == READ;
        req.rready = state == VERIFY;
    end
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state <= FETCH; index <= 0; progress <= 0;
            aw_pending <= 1; w_pending <= 1; watchdog <= 0;
        end else begin
            if (state == FINISHED || state == FAILED) watchdog <= 0;
            else watchdog <= watchdog + 1'b1;
            case (state)
                FETCH: begin state <= WRITE; aw_pending <= 1; w_pending <= 1; end
                WRITE: begin
                    if (req.awvalid && rsp.awready) aw_pending <= 0;
                    if (req.wvalid && rsp.wready) w_pending <= 0;
                    if ((!aw_pending || rsp.awready) && (!w_pending || rsp.wready)) state <= RESPONSE;
                end
                RESPONSE: if (rsp.bvalid) begin
                    watchdog <= 0;
                    state <= rsp.bresp == AXI_OKAY && rsp.bid == 2 ? READ : FAILED;
                end
                READ: if (rsp.arready) state <= VERIFY;
                VERIFY: if (rsp.rvalid) begin
                    watchdog <= 0;
                    if (rsp.rresp != AXI_OKAY || rsp.rid != 2 || !rsp.rlast || rsp.rdata != image_word)
                        state <= FAILED;
                    else begin
                        progress <= progress + 1'b1;
                        if (index == INDEX_BITS'(IMAGE_WORDS-1)) state <= FINISHED;
                        else begin index <= index + 1'b1; state <= FETCH; end
                    end
                end
                FINISHED, FAILED: ;
                default: state <= FAILED;
            endcase
            if (state != FINISHED && state != FAILED && watchdog == $bits(watchdog)'(TIMEOUT_CYCLES-1))
                state <= FAILED;
        end
    end
endmodule
