`timescale 1ns/1ps
// Dual-clock ready/valid FIFO. DEPTH is a power of two, at least four.
// Both domains share an asynchronously asserted reset; release is synchronized
// separately in each domain. Payload bits only cross inside dual-port storage.
module async_fifo #(
    parameter int WIDTH = 32,
    parameter int DEPTH = 4
) (
    input  logic wr_clk,
    input  logic rd_clk,
    input  logic rst_n,
    input  logic in_valid,
    output logic in_ready,
    input  logic [WIDTH-1:0] in_data,
    output logic out_valid,
    input  logic out_ready,
    output logic [WIDTH-1:0] out_data,
    output logic [$clog2(DEPTH):0] wr_level,
    output logic [$clog2(DEPTH):0] rd_level
);
    localparam int PTR = $clog2(DEPTH);
    logic [WIDTH-1:0] storage [DEPTH];
    logic [PTR:0] wr_bin, wr_gray, rd_bin, rd_gray;
    (* async_reg = "true" *) logic [PTR:0] rd_gray_w1, rd_gray_w2;
    (* async_reg = "true" *) logic [PTR:0] wr_gray_r1, wr_gray_r2;
    (* async_reg = "true" *) logic [1:0] wr_release, rd_release;
    logic [PTR:0] wr_next_bin, wr_next_gray, rd_next_bin, rd_next_gray;
    logic full, empty;

    function automatic logic [PTR:0] gray_to_bin(input logic [PTR:0] g);
        logic [PTR:0] b;
        b[PTR] = g[PTR];
        for (int i = PTR-1; i >= 0; i--) b[i] = b[i+1] ^ g[i];
        return b;
    endfunction

    assign wr_next_bin = wr_bin + {{PTR{1'b0}}, (in_valid && in_ready)};
    assign wr_next_gray = (wr_next_bin >> 1) ^ wr_next_bin;
    assign rd_next_bin = rd_bin + {{PTR{1'b0}}, (out_valid && out_ready)};
    assign rd_next_gray = (rd_next_bin >> 1) ^ rd_next_bin;
    assign full = wr_gray == {~rd_gray_w2[PTR:PTR-1], rd_gray_w2[PTR-2:0]};
    assign empty = rd_gray == wr_gray_r2;
    assign in_ready = wr_release[1] && !full;
    assign out_valid = rd_release[1] && !empty;
    assign out_data = storage[rd_bin[PTR-1:0]];
    assign wr_level = wr_bin - gray_to_bin(rd_gray_w2);
    assign rd_level = gray_to_bin(wr_gray_r2) - rd_bin;

    always_ff @(posedge wr_clk or negedge rst_n) begin
        if (!rst_n) wr_release <= '0;
        else wr_release <= {wr_release[0], 1'b1};
    end
    always_ff @(posedge rd_clk or negedge rst_n) begin
        if (!rst_n) rd_release <= '0;
        else rd_release <= {rd_release[0], 1'b1};
    end

    // Payload RAM has no reset. Keeping its write process separate prevents
    // the asynchronous reset from becoming an unsynchronized RAM write-enable.
    always_ff @(posedge wr_clk) begin
        if (in_valid && in_ready) storage[wr_bin[PTR-1:0]] <= in_data;
    end
    always_ff @(posedge wr_clk or negedge wr_release[1]) begin
        if (!wr_release[1]) begin
            wr_bin <= '0;
            wr_gray <= '0;
            rd_gray_w1 <= '0;
            rd_gray_w2 <= '0;
        end else begin
            rd_gray_w1 <= rd_gray;
            rd_gray_w2 <= rd_gray_w1;
            if (in_valid && in_ready) begin
                wr_bin <= wr_next_bin;
                wr_gray <= wr_next_gray;
            end
        end
    end
    always_ff @(posedge rd_clk or negedge rd_release[1]) begin
        if (!rd_release[1]) begin
            rd_bin <= '0;
            rd_gray <= '0;
            wr_gray_r1 <= '0;
            wr_gray_r2 <= '0;
        end else begin
            wr_gray_r1 <= wr_gray;
            wr_gray_r2 <= wr_gray_r1;
            if (out_valid && out_ready) begin
                rd_bin <= rd_next_bin;
                rd_gray <= rd_next_gray;
            end
        end
    end
endmodule
