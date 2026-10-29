// EX stage: immediates, ALU, multiplier, branch/jump resolution, memory
// address generation, CSR instruction legality, and synchronous exception
// detection. Produces the record EX hands to MEM.
module rv32_execute
    import rv32_pkg::*;
#(
    parameter bit WAIT_MEMORY = 0,
    parameter bit ENABLE_PRIVILEGE = 0
) (
    input  execute_stage_t ex_stage,
    input  logic [1:0]     privilege,
    // Only TVM/TW/TSR are inspected here.
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [31:0]    csr_mstatus,
    /* verilator lint_on UNUSEDSIGNAL */
    input  logic [31:0]    csr_mepc,
    input  logic [31:0]    csr_sepc,
    input  logic [31:0]    csr_old,
    input  logic [31:0]    csr_new,
    input  logic           csr_exists,
    input  logic           csr_write_attempt,
    input  logic [31:0]    div_quotient,
    input  logic [31:0]    div_remainder,
    input  logic           div_stall,
    input  logic           fence_wait,
    input  logic           fence_i_ready,
    input  logic           fence_i_fault,
    input  logic           pc_allowed,            // PMP execute check of ex_stage.pc
    input  logic           data_protection_fault, // PMP check of ex_memory_*
    output result_stage_t  ex_result,
    output logic           redirect,
    output logic [31:0]    redirect_pc,
    output logic [31:0]    ex_memory_addr,
    output logic [1:0]     ex_memory_size,
    output logic           ex_memory_read,
    output logic           ex_memory_write
);
    logic [4:0]  ex_rd;
    logic [31:0] imm_i, imm_s, imm_b, imm_u, imm_j;
    logic signed [63:0] mul_ss, mul_su;
    logic [63:0] mul_uu;

    assign ex_rd = ex_stage.insn[11:7];
    assign imm_i = {{20{ex_stage.insn[31]}}, ex_stage.insn[31:20]};
    assign imm_s = {{20{ex_stage.insn[31]}}, ex_stage.insn[31:25], ex_stage.insn[11:7]};
    assign imm_b = {{19{ex_stage.insn[31]}}, ex_stage.insn[31], ex_stage.insn[7],
                    ex_stage.insn[30:25], ex_stage.insn[11:8], 1'b0};
    assign imm_u = {ex_stage.insn[31:12], 12'b0};
    assign imm_j = {{11{ex_stage.insn[31]}}, ex_stage.insn[31], ex_stage.insn[19:12],
                    ex_stage.insn[20], ex_stage.insn[30:21], 1'b0};
    // Share the unsigned 32x32 product across all MUL variants. Signed high
    // halves differ by subtracting the other operand for each negative input.
    assign mul_ss = $signed({mul_uu[63:32] -
        (ex_stage.rs1_value[31] ? ex_stage.rs2_value : 32'b0) -
        (ex_stage.rs2_value[31] ? ex_stage.rs1_value : 32'b0), mul_uu[31:0]});
    assign mul_su = $signed({mul_uu[63:32] -
        (ex_stage.rs1_value[31] ? ex_stage.rs2_value : 32'b0), mul_uu[31:0]});
    assign mul_uu = ex_stage.rs1_value * ex_stage.rs2_value;
    // Decode the data-check inputs independently of the instruction check.
    // Gating the address with instruction permission serialized two PMP
    // networks on the execute-to-memory path. Fault priority stays in EX.
    assign ex_memory_addr = ex_stage.rs1_value +
        (ex_stage.insn[6:0] == 7'h03 ? imm_i : ex_stage.insn[6:0] == 7'h23 ? imm_s : 32'b0);
    assign ex_memory_size = ex_stage.insn[6:0] == 7'h2f ? 2'd2 : ex_stage.insn[13:12];
    assign ex_memory_read = ex_stage.insn[6:0] == 7'h03 ||
        (ex_stage.insn[6:0] == 7'h2f && ex_stage.insn[31:27] != 5'b00011);
    assign ex_memory_write = ex_stage.insn[6:0] == 7'h23 ||
        (ex_stage.insn[6:0] == 7'h2f && ex_stage.insn[31:27] != 5'b00010);

    always_comb begin
        ex_result = '0;
        ex_result.valid = ex_stage.valid;
        ex_result.pc = ex_stage.pc;
        ex_result.insn = ex_stage.insn;
        ex_result.next_pc = ex_stage.pc + 4;
        redirect = 1'b0;
        redirect_pc = 32'b0;
        if (ex_stage.valid) begin
            if (ex_stage.fault || !pc_allowed) begin
                ex_result.trap = 1;
                ex_result.cause = 1;
                ex_result.tval = ex_stage.pc;
            end else case (ex_stage.insn[6:0])
                7'h37, 7'h17: begin // LUI, AUIPC
                    ex_result.rd = ex_rd;
                    ex_result.result = ex_stage.insn[6:0] == 7'h37 ?
                        imm_u : ex_stage.pc + imm_u;
                end
                7'h13: begin // OP-IMM
                    ex_result.rd = ex_rd;
                    case (ex_stage.insn[14:12])
                        3'b000: ex_result.result = ex_stage.rs1_value + imm_i;
                        3'b010: ex_result.result = ($signed(ex_stage.rs1_value) < $signed(imm_i)) ? 1 : 0;
                        3'b011: ex_result.result = (ex_stage.rs1_value < imm_i) ? 1 : 0;
                        3'b100: ex_result.result = ex_stage.rs1_value ^ imm_i;
                        3'b110: ex_result.result = ex_stage.rs1_value | imm_i;
                        3'b111: ex_result.result = ex_stage.rs1_value & imm_i;
                        3'b001: begin
                            if (ex_stage.insn[31:25] != 0) ex_result.trap = 1;
                            else ex_result.result = ex_stage.rs1_value << ex_stage.insn[24:20];
                        end
                        3'b101: begin
                            if (ex_stage.insn[31:25] == 0)
                                ex_result.result = ex_stage.rs1_value >> ex_stage.insn[24:20];
                            else if (ex_stage.insn[31:25] == 7'h20)
                                ex_result.result = $signed(ex_stage.rs1_value) >>> ex_stage.insn[24:20];
                            else ex_result.trap = 1;
                        end
                        default: ex_result.trap = 1;
                    endcase
                end
                7'h33: begin // OP
                    ex_result.rd = ex_rd;
                    if (ex_stage.insn[31:25] == 7'h01) begin
                        case (ex_stage.insn[14:12])
                            3'b000: ex_result.result = mul_ss[31:0];
                            3'b001: ex_result.result = mul_ss[63:32];
                            3'b010: ex_result.result = mul_su[63:32];
                            3'b011: ex_result.result = mul_uu[63:32];
                            3'b100, 3'b101: ex_result.result = div_quotient;
                            3'b110, 3'b111: ex_result.result = div_remainder;
                            default: ex_result.trap = 1;
                        endcase
                    end else if (ex_stage.insn[31:25] == 0) begin
                        case (ex_stage.insn[14:12])
                            3'b000: ex_result.result = ex_stage.rs1_value + ex_stage.rs2_value;
                            3'b001: ex_result.result = ex_stage.rs1_value << ex_stage.rs2_value[4:0];
                            3'b010: ex_result.result = ($signed(ex_stage.rs1_value) < $signed(ex_stage.rs2_value)) ? 1 : 0;
                            3'b011: ex_result.result = (ex_stage.rs1_value < ex_stage.rs2_value) ? 1 : 0;
                            3'b100: ex_result.result = ex_stage.rs1_value ^ ex_stage.rs2_value;
                            3'b101: ex_result.result = ex_stage.rs1_value >> ex_stage.rs2_value[4:0];
                            3'b110: ex_result.result = ex_stage.rs1_value | ex_stage.rs2_value;
                            3'b111: ex_result.result = ex_stage.rs1_value & ex_stage.rs2_value;
                            default: ex_result.trap = 1;
                        endcase
                    end else if (ex_stage.insn[31:25] == 7'h20 && ex_stage.insn[14:12] == 0)
                        ex_result.result = ex_stage.rs1_value - ex_stage.rs2_value;
                    else if (ex_stage.insn[31:25] == 7'h20 && ex_stage.insn[14:12] == 3'b101)
                        ex_result.result = $signed(ex_stage.rs1_value) >>> ex_stage.rs2_value[4:0];
                    else ex_result.trap = 1;
                end
                7'h03, 7'h23: begin // loads and stores
                    ex_result.addr = ex_memory_addr;
                    case (ex_stage.insn[14:12])
                        3'b000, 3'b100: ex_result.mem_mask = 4'b0001 << ex_result.addr[1:0];
                        3'b001, 3'b101: ex_result.mem_mask = 4'b0011 << ex_result.addr[1:0];
                        3'b010: ex_result.mem_mask = 4'b1111;
                        default: ex_result.trap = 1;
                    endcase
                    if (ex_stage.insn[6:0] == 7'h23 && ex_stage.insn[14:12] inside {3'b100, 3'b101})
                        ex_result.trap = 1;
                    if (!ex_result.trap) begin
                        if ((ex_stage.insn[14:12] inside {3'b001, 3'b101}) && ex_result.addr[0] ||
                            ex_stage.insn[14:12] == 3'b010 && ex_result.addr[1:0] != 0) begin
                            ex_result.trap = 1;
                            ex_result.cause = ex_stage.insn[6:0] == 7'h03 ? 32'd4 : 32'd6;
                            ex_result.tval = ex_result.addr;
                        end else if (ex_stage.insn[6:0] == 7'h03) begin
                            ex_result.load = 1;
                            ex_result.rd = ex_rd;
                        end else begin
                            ex_result.store = 1;
                            ex_result.store_data = ex_stage.rs2_value << (8 * ex_result.addr[1:0]);
                        end
                    end
                end
                7'h2f: begin // RV32A word atomics
                    ex_result.addr = ex_stage.rs1_value;
                    ex_result.rd = ex_rd;
                    ex_result.mem_mask = 4'hf;
                    ex_result.atomic_op = ex_stage.insn[31:27];
                    ex_result.atomic_operand = ex_stage.rs2_value;
                    if (ex_stage.insn[14:12] != 3'b010) ex_result.trap = 1;
                    else if (ex_stage.insn[31:27] == 5'b00010 && ex_stage.insn[24:20] == 0) begin
                        ex_result.atomic_kind = 1;
                        ex_result.load = 1;
                    end else if (ex_stage.insn[31:27] == 5'b00011) ex_result.atomic_kind = 2;
                    else if (ex_stage.insn[31:27] inside {5'b00000, 5'b00001, 5'b00100,
                                                            5'b01000, 5'b01100, 5'b10000,
                                                            5'b10100, 5'b11000, 5'b11100}) begin
                        ex_result.atomic_kind = 3;
                        ex_result.load = 1;
                    end else ex_result.trap = 1;
                    if (!ex_result.trap && ex_result.addr[1:0] != 0) begin
                        ex_result.trap = 1;
                        ex_result.cause = ex_result.atomic_kind == 1 ? 32'd4 : 32'd6;
                        ex_result.tval = ex_result.addr;
                    end
                end
                7'h63: begin // conditional branches
                    case (ex_stage.insn[14:12])
                        3'b000: redirect = ex_stage.rs1_value == ex_stage.rs2_value;
                        3'b001: redirect = ex_stage.rs1_value != ex_stage.rs2_value;
                        3'b100: redirect = $signed(ex_stage.rs1_value) < $signed(ex_stage.rs2_value);
                        3'b101: redirect = $signed(ex_stage.rs1_value) >= $signed(ex_stage.rs2_value);
                        3'b110: redirect = ex_stage.rs1_value < ex_stage.rs2_value;
                        3'b111: redirect = ex_stage.rs1_value >= ex_stage.rs2_value;
                        default: ex_result.trap = 1;
                    endcase
                    if (redirect) redirect_pc = ex_stage.pc + imm_b;
                end
                7'h6f, 7'h67: begin // JAL, JALR
                    if (ex_stage.insn[6:0] == 7'h67 && ex_stage.insn[14:12] != 0)
                        ex_result.trap = 1;
                    else begin
                        redirect_pc = ex_stage.insn[6:0] == 7'h6f ?
                            ex_stage.pc + imm_j : (ex_stage.rs1_value + imm_i) & 32'hffff_fffe;
                        ex_result.rd = ex_rd;
                        ex_result.result = ex_stage.pc + 32'd4;
                        redirect = 1;
                    end
                end
                7'h0f: begin // serializing fences; FENCE.I waits for cache maintenance
                    if (ex_stage.insn[14:12] == 3'b000 && ex_rd == 0 &&
                        ex_stage.insn[19:15] == 0 &&
                        ex_stage.insn[31:28] inside {4'h0, 4'h8}) begin
                        // All older stores have retired before this reaches EX.
                    end else if (ex_stage.insn[14:12] == 3'b001 && ex_rd == 0 &&
                                 ex_stage.insn[19:15] == 0 && ex_stage.insn[31:20] == 0) begin
                        redirect = !fence_wait;
                        redirect_pc = ex_stage.pc + 32'd4;
                        if (WAIT_MEMORY && fence_i_ready && fence_i_fault) begin
                            ex_result.fatal = 1;
                            redirect = 0;
                            ex_result.trap = 1;
                            ex_result.cause = 7;
                            ex_result.tval = ex_stage.pc;
                        end
                    end else ex_result.trap = 1;
                end
                7'h73: begin
                    if (ex_stage.insn == 32'h0000_0073) begin
                        ex_result.trap = 1;
                        ex_result.cause = 32'(privilege) + 8;
                    end else if (ex_stage.insn == 32'h0010_0073) begin
                        ex_result.trap = 1;
                        ex_result.cause = 3; // EBREAK
                        ex_result.tval = ex_stage.pc;
                    end else if (ENABLE_PRIVILEGE && ex_stage.insn == 32'h3020_0073 && privilege == 3) begin
                        ex_result.next_pc = csr_mepc;
                    end else if (ENABLE_PRIVILEGE && ex_stage.insn == 32'h1020_0073 &&
                                 privilege != 0 && !(privilege == 1 && csr_mstatus[22])) begin
                        ex_result.next_pc = csr_sepc;
                    end else if (ENABLE_PRIVILEGE && ex_stage.insn == 32'h1050_0073 &&
                                 privilege != 0 && !(privilege == 1 && csr_mstatus[21])) begin
                        // WFI is a permitted no-op; pending interrupts still enter precisely.
                    end else if (ENABLE_PRIVILEGE && (ex_stage.insn & 32'hfe00_7fff) == 32'h1200_0073 &&
                                 privilege != 0 && !(privilege == 1 && csr_mstatus[20])) begin
                        // Bare mode has no translations to invalidate yet.
                    end else if ((ex_stage.insn[14:12] inside {3'b001, 3'b010, 3'b011,
                                                                3'b101, 3'b110, 3'b111}) &&
                                 csr_exists && privilege >= ex_stage.insn[29:28] &&
                                 !(csr_write_attempt &&
                                   (ex_stage.insn[31:30] == 2'b11 ||
                                    (!ENABLE_PRIVILEGE && ex_stage.insn[31:20] inside {12'h301, 12'h344})))) begin
                        ex_result.rd = ex_rd;
                        ex_result.result = csr_old;
                        if (csr_write_attempt) begin
                            ex_result.csr_write = 1;
                            ex_result.csr_addr = ex_stage.insn[31:20];
                            ex_result.csr_data = csr_new;
                        end
                    end else ex_result.trap = 1;
                end
                default: ex_result.trap = 1;
            endcase
            if (redirect) ex_result.next_pc = redirect_pc;
            if (redirect && redirect_pc[1:0] != 0) begin
                redirect = 0;
                ex_result.trap = 1;
                ex_result.cause = 0;
                ex_result.tval = redirect_pc;
            end
            if (!ex_result.trap && (ex_result.load || ex_result.store || ex_result.atomic_kind != 0)) begin
                if (data_protection_fault) begin
                    ex_result.trap = 1;
                    ex_result.cause = ex_result.store || ex_result.atomic_kind inside {2,3} ? 7 : 5;
                    ex_result.tval = ex_result.addr;
                end
            end
            if (ex_result.trap && ex_result.cause == 0 && ex_result.tval == 0) begin
                ex_result.cause = 2;
                ex_result.tval = ex_stage.insn;
            end
            if (ex_result.trap) begin
                ex_result.rd = 0;
                ex_result.load = 0;
                ex_result.store = 0;
                ex_result.mem_mask = 0;
                ex_result.atomic_kind = 0;
                ex_result.csr_write = 0;
            end
            if (div_stall || fence_wait) ex_result.valid = 0;
        end
    end
endmodule
