`timescale 1ns/1ps
// Standalone DDR bring-up traffic. Master 0 runs two 64 KiB write/read
// sweeps; master 1 generates single-beat CPU-like traffic during sweep 2.
// The second master is a surrogate until the CPU is connected in checkpoint 9.
module checkpoint8_traffic (
    input  logic clk,
    input  logic rst_n,
    input  logic run,
    output axi128_pkg::axi_req_t dma_req,
    input  axi128_pkg::axi_rsp_t dma_rsp,
    output axi128_pkg::axi_req_t cpu_req,
    input  axi128_pkg::axi_rsp_t cpu_rsp,
    output logic done,
    output logic [31:0] baseline_write_cycles,
    output logic [31:0] baseline_read_cycles,
    output logic [31:0] contended_write_cycles,
    output logic [31:0] contended_read_cycles,
    output logic [31:0] dma_errors,
    output logic [31:0] cpu_errors,
    output logic [31:0] cpu_round_trips
);
    import axi128_pkg::*;
    typedef enum logic [2:0] {P_WAIT, P_BASE_START, P_BASE_WAIT,
                              P_CONT_START, P_CONT_WAIT, P_DONE} phase_t;
    typedef enum logic [2:0] {D_IDLE, D_AW, D_W, D_B, D_AR, D_R} dma_state_t;
    typedef enum logic [2:0] {C_IDLE, C_AW, C_W, C_B, C_AR, C_R} cpu_state_t;
    phase_t phase;
    dma_state_t dma_state;
    cpu_state_t cpu_state;
    logic [7:0] burst;
    logic [3:0] beat;
    logic [3:0] cpu_index;
    logic dma_finished;
    logic cpu_enable;
    logic [31:0] write_elapsed, read_elapsed;
    logic [31:0] write_result, read_result;

    function automatic logic [127:0] dma_pattern(input logic [7:0] b,
                                                   input logic [3:0] w);
        logic [127:0] value;
        for (int lane = 0; lane < 16; lane++)
            value[lane*8 +: 8] = 8'(32'(b) ^ (32'(w) << 4) ^ lane ^ 32'h5a);
        return value;
    endfunction

    function automatic logic [127:0] cpu_pattern(input logic [3:0] index);
        logic [127:0] value;
        for (int lane = 0; lane < 16; lane++)
            value[lane*8 +: 8] = 8'(32'(index) ^ lane ^ 32'ha5);
        return value;
    endfunction

    assign cpu_enable = (phase == P_CONT_START || phase == P_CONT_WAIT);
    assign done = phase == P_DONE;

    always_comb begin
        dma_req = '0;
        case (dma_state)
            D_AW: begin
                dma_req.awvalid = 1'b1;
                dma_req.awaddr = 32'h8000_0000 + {16'b0, burst, 8'b0};
                dma_req.awlen = 4'd15;
                dma_req.awsize = 3'd4;
                dma_req.awid = 4'd0;
            end
            D_W: begin
                dma_req.wvalid = 1'b1;
                dma_req.wdata = dma_pattern(burst, beat);
                dma_req.wstrb = 16'hffff;
                dma_req.wlast = beat == 4'd15;
            end
            D_B: dma_req.bready = 1'b1;
            D_AR: begin
                dma_req.arvalid = 1'b1;
                dma_req.araddr = 32'h8000_0000 + {16'b0, burst, 8'b0};
                dma_req.arlen = 4'd15;
                dma_req.arsize = 3'd4;
                dma_req.arid = 4'd0;
            end
            D_R: dma_req.rready = 1'b1;
            default: ;
        endcase
        cpu_req = '0;
        case (cpu_state)
            C_AW: begin
                cpu_req.awvalid = 1'b1;
                cpu_req.awaddr = 32'h8002_0000 + {24'b0, cpu_index, 4'b0};
                cpu_req.awlen = 4'd0;
                cpu_req.awsize = 3'd4;
                cpu_req.awid = 4'd1;
            end
            C_W: begin
                cpu_req.wvalid = 1'b1;
                cpu_req.wdata = cpu_pattern(cpu_index);
                cpu_req.wstrb = 16'hffff;
                cpu_req.wlast = 1'b1;
            end
            C_B: cpu_req.bready = 1'b1;
            C_AR: begin
                cpu_req.arvalid = 1'b1;
                cpu_req.araddr = 32'h8002_0000 + {24'b0, cpu_index, 4'b0};
                cpu_req.arlen = 4'd0;
                cpu_req.arsize = 3'd4;
                cpu_req.arid = 4'd1;
            end
            C_R: cpu_req.rready = 1'b1;
            default: ;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase <= P_WAIT;
            baseline_write_cycles <= 0;
            baseline_read_cycles <= 0;
            contended_write_cycles <= 0;
            contended_read_cycles <= 0;
        end else begin
            case (phase)
                P_WAIT: if (run) phase <= P_BASE_START;
                P_BASE_START: phase <= P_BASE_WAIT;
                P_BASE_WAIT: if (dma_finished) begin
                    baseline_write_cycles <= write_result;
                    baseline_read_cycles <= read_result;
                    phase <= P_CONT_START;
                end
                P_CONT_START: phase <= P_CONT_WAIT;
                P_CONT_WAIT: if (dma_finished) begin
                    contended_write_cycles <= write_result;
                    contended_read_cycles <= read_result;
                    phase <= P_DONE;
                end
                default: ;
            endcase
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dma_state <= D_IDLE;
            burst <= 0;
            beat <= 0;
            dma_finished <= 0;
            write_elapsed <= 0;
            read_elapsed <= 0;
            write_result <= 0;
            read_result <= 0;
            dma_errors <= 0;
        end else begin
            dma_finished <= 0;
            if (dma_state == D_AW || dma_state == D_W || dma_state == D_B)
                write_elapsed <= write_elapsed + 1;
            if (dma_state == D_AR || dma_state == D_R)
                read_elapsed <= read_elapsed + 1;
            case (dma_state)
                D_IDLE: if (phase == P_BASE_START || phase == P_CONT_START) begin
                    burst <= 0;
                    beat <= 0;
                    write_elapsed <= 0;
                    read_elapsed <= 0;
                    dma_state <= D_AW;
                end
                D_AW: if (dma_rsp.awready) dma_state <= D_W;
                D_W: if (dma_rsp.wready) begin
                    if (beat == 4'd15) begin
                        beat <= 0;
                        dma_state <= D_B;
                    end else beat <= beat + 1'b1;
                end
                D_B: if (dma_rsp.bvalid) begin
                    if (dma_rsp.bresp != AXI_OKAY || dma_rsp.bid != 4'd0)
                        dma_errors <= dma_errors + 1;
                    if (burst == 8'hff) begin
                        write_result <= write_elapsed + 1;
                        burst <= 0;
                        dma_state <= D_AR;
                    end else begin
                        burst <= burst + 1'b1;
                        dma_state <= D_AW;
                    end
                end
                D_AR: if (dma_rsp.arready) dma_state <= D_R;
                D_R: if (dma_rsp.rvalid) begin
                    if (dma_rsp.rresp != AXI_OKAY || dma_rsp.rid != 4'd0 ||
                        dma_rsp.rlast != (beat == 4'd15) ||
                        dma_rsp.rdata != dma_pattern(burst, beat)) begin
`ifndef SYNTHESIS
                        $display("DMA mismatch burst=%0d beat=%0d data=%h expected=%h resp=%b id=%h last=%b",
                                 burst, beat, dma_rsp.rdata, dma_pattern(burst, beat),
                                 dma_rsp.rresp, dma_rsp.rid, dma_rsp.rlast);
`endif
                        dma_errors <= dma_errors + 1;
                    end
                    if (beat == 4'd15) begin
                        beat <= 0;
                        if (burst == 8'hff) begin
                            read_result <= read_elapsed + 1;
                            dma_finished <= 1;
                            dma_state <= D_IDLE;
                        end else begin
                            burst <= burst + 1'b1;
                            dma_state <= D_AR;
                        end
                    end else beat <= beat + 1'b1;
                end
                default: dma_state <= D_IDLE;
            endcase
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cpu_state <= C_IDLE;
            cpu_index <= 0;
            cpu_errors <= 0;
            cpu_round_trips <= 0;
        end else begin
            case (cpu_state)
                C_IDLE: if (cpu_enable) cpu_state <= C_AW;
                C_AW: if (cpu_rsp.awready) cpu_state <= C_W;
                C_W: if (cpu_rsp.wready) cpu_state <= C_B;
                C_B: if (cpu_rsp.bvalid) begin
                    if (cpu_rsp.bresp != AXI_OKAY || cpu_rsp.bid != 4'd1)
                        cpu_errors <= cpu_errors + 1;
                    cpu_state <= C_AR;
                end
                C_AR: if (cpu_rsp.arready) cpu_state <= C_R;
                C_R: if (cpu_rsp.rvalid) begin
                    if (cpu_rsp.rresp != AXI_OKAY || cpu_rsp.rid != 4'd1 ||
                        !cpu_rsp.rlast || cpu_rsp.rdata != cpu_pattern(cpu_index))
                        cpu_errors <= cpu_errors + 1;
                    cpu_round_trips <= cpu_round_trips + 1;
                    cpu_index <= cpu_index + 1'b1;
                    if (cpu_enable) cpu_state <= C_AW;
                    else cpu_state <= C_IDLE;
                end
                default: cpu_state <= C_IDLE;
            endcase
        end
    end
endmodule
