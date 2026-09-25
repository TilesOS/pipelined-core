// Harness fixture only. This is not CPU RTL: it emits smoke.S events.
module trace_fixture (
    input  logic        clk,
    input  logic        rst_n,
    output logic        retire_valid,
    output logic [31:0] retire_pc,
    output logic [31:0] retire_insn,
    output logic [1:0]  retire_priv,
    output logic [4:0]  retire_rd,
    output logic [31:0] retire_rd_data,
    output logic [31:0] retire_mem_addr,
    output logic [3:0]  retire_mem_rmask,
    output logic [3:0]  retire_mem_wmask,
    output logic [31:0] retire_mem_wdata,
    output logic        retire_trap,
    output logic [31:0] retire_cause,
    output logic [31:0] retire_tval,
    output logic        done
);
    logic [2:0] index;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            index <= 0;
            retire_valid <= 0;
            retire_pc <= 0;
            retire_insn <= 0;
            retire_priv <= 0;
            retire_rd <= 0;
            retire_rd_data <= 0;
            retire_mem_addr <= 0;
            retire_mem_rmask <= 0;
            retire_mem_wmask <= 0;
            retire_mem_wdata <= 0;
            retire_trap <= 0;
            retire_cause <= 0;
            retire_tval <= 0;
            done <= 0;
        end else begin
            retire_valid <= 0;
            retire_rd <= 0;
            retire_rd_data <= 0;
            retire_mem_addr <= 0;
            retire_mem_rmask <= 0;
            retire_mem_wmask <= 0;
            retire_mem_wdata <= 0;
            retire_trap <= 0;
            retire_cause <= 0;
            retire_tval <= 0;
            retire_priv <= 2'd3;
            if (index < 3'd7) begin
                retire_valid <= 1;
                retire_pc <= 32'h8000_0000 + {27'd0, index, 2'b00};
                index <= index + 1'b1;
                unique case (index)
                    3'd0: begin
                        retire_insn <= 32'h0050_0093;
                        retire_rd <= 5'd1;
                        retire_rd_data <= 32'd5;
                    end
                    3'd1: begin
                        retire_insn <= 32'h0070_8113;
                        retire_rd <= 5'd2;
                        retire_rd_data <= 32'd12;
                    end
                    3'd2: begin
                        retire_insn <= 32'h8000_11b7;
                        retire_rd <= 5'd3;
                        retire_rd_data <= 32'h8000_1000;
                    end
                    3'd3: begin
                        retire_insn <= 32'h0021_a023;
                        retire_mem_addr <= 32'h8000_1000;
                        retire_mem_wmask <= 4'hf;
                        retire_mem_wdata <= 32'd12;
                    end
                    3'd4: begin
                        retire_insn <= 32'h0001_a203;
                        retire_rd <= 5'd4;
                        retire_rd_data <= 32'd12;
                        retire_mem_addr <= 32'h8000_1000;
                        retire_mem_rmask <= 4'hf;
                    end
                    3'd5: begin
                        retire_insn <= 32'h0012_0293;
                        retire_rd <= 5'd5;
                        retire_rd_data <= 32'd13;
                    end
                    3'd6: begin
                        retire_insn <= 32'hffff_ffff;
                        retire_trap <= 1;
                        retire_cause <= 32'd2;
                        retire_tval <= 32'hffff_ffff;
                    end
                    default: retire_insn <= 0;
                endcase
            end else begin
                done <= 1;
            end
        end
    end
endmodule
