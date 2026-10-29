// Machine/supervisor CSRs, privilege mode, PMP registers, interrupt
// selection and trap entry/return. CSR instructions read and legalize in EX
// (csr_old/csr_new) and write at WB retirement, like every other effect.
module rv32_csr
    import rv32_pkg::*;
#(
    parameter bit ENABLE_PRIVILEGE = 0
) (
    input  logic          clk,
    input  logic          rst_n,
    input  logic          msip_irq, mtip_irq, meip_irq, seip_irq,
    input  logic [63:0]   time_value,
    // EX read and write-value legalization.
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [31:0]   ex_insn, // opcode and rd are decoded by EX
    /* verilator lint_on UNUSEDSIGNAL */
    input  logic [31:0]   ex_rs1_value,
    output logic [31:0]   csr_old,
    output logic [31:0]   csr_new,
    output logic          csr_exists,
    output logic          csr_write_attempt,
    // WB retirement, trap entry and xRET.
    input  logic          advance,
    // Only the commit, trap and CSR fields are inspected.
    /* verilator lint_off UNUSEDSIGNAL */
    input  result_stage_t wb_commit,
    /* verilator lint_on UNUSEDSIGNAL */
    input  logic          xret_commit,
    input  logic          trap_enter,
    input  logic          take_irq,
    input  logic [31:0]   arch_pc,
    output logic          irq_pending,
    output logic [31:0]   trap_pc,
    output logic [31:0]   trap_cause,
    output logic [31:0]   trap_vector,
    // State observed by the rest of the core.
    output logic [1:0]    privilege,
    output logic [1:0]    data_privilege,
    output logic [31:0]   csr_mstatus,
    output logic [31:0]   csr_mepc,
    output logic [31:0]   csr_sepc,
    output logic [7:0]    pmpcfg [8],
    output logic [31:0]   pmpaddr [8]
);
    logic [31:0] csr_operand;
    logic [31:0] csr_mie, csr_mtvec, csr_mscratch, csr_mcause, csr_mtval;
    logic [63:0] csr_mcycle, csr_minstret;
    logic [31:0] csr_medeleg, csr_mideleg, csr_mip_sw;
    logic [31:0] csr_stvec, csr_sscratch, csr_scause, csr_stval;
    logic [31:0] csr_mcounteren, csr_scounteren, csr_mcountinhibit;
    logic [31:0] pending_irqs, eligible_irqs, irq_cause, trap_value;
    logic trap_to_s;

    assign data_privilege = privilege == 3 && csr_mstatus[17] ? csr_mstatus[12:11] : privilege;

    assign pending_irqs = csr_mip_sw | (msip_irq ? 32'h8 : 0) |
        (mtip_irq ? 32'h80 : 0) | (meip_irq ? 32'h800 : 0) | (seip_irq ? 32'h200 : 0);
    always_comb begin
        eligible_irqs = 0;
        for (int i = 0; i < 12; i++)
            if (csr_mie[i] && pending_irqs[i]) begin
                if (csr_mideleg[i])
                    eligible_irqs[i] = privilege == 0 || (privilege == 1 && csr_mstatus[1]);
                else eligible_irqs[i] = privilege != 3 || csr_mstatus[3];
            end
        irq_cause = 0;
        if (eligible_irqs[11]) irq_cause = 11;
        else if (eligible_irqs[3]) irq_cause = 3;
        else if (eligible_irqs[7]) irq_cause = 7;
        else if (eligible_irqs[9]) irq_cause = 9;
        else if (eligible_irqs[1]) irq_cause = 1;
        else if (eligible_irqs[5]) irq_cause = 5;
    end
    assign irq_pending = ENABLE_PRIVILEGE && |eligible_irqs;
    assign trap_pc = take_irq ? arch_pc : wb_commit.pc;
    assign trap_cause = take_irq ? (32'h8000_0000 | irq_cause) : wb_commit.cause;
    assign trap_value = take_irq ? 0 : wb_commit.tval;
    assign trap_to_s = ENABLE_PRIVILEGE && privilege != 3 &&
        (take_irq ? csr_mideleg[irq_cause[4:0]] : csr_medeleg[wb_commit.cause[4:0]]);
    assign trap_vector = ((trap_to_s ? csr_stvec : csr_mtvec) & 32'hffff_fffc) +
        ((take_irq && (trap_to_s ? csr_stvec[0] : csr_mtvec[0])) ? irq_cause * 4 : 0);

    always_comb begin
        csr_exists = 1;
        csr_old = 0;
        case (ex_insn[31:20])
            12'h300: csr_old = csr_mstatus;
            12'h301: csr_old = ENABLE_PRIVILEGE ? 32'h4014_1101 : 32'h4000_1101;
            12'h304: csr_old = csr_mie;
            12'h305: csr_old = csr_mtvec;
            12'h340: csr_old = csr_mscratch;
            12'h341: csr_old = csr_mepc;
            12'h342: csr_old = csr_mcause;
            12'h343: csr_old = csr_mtval;
            12'h344: csr_old = ENABLE_PRIVILEGE ? pending_irqs : 0;
            12'h100: begin csr_old = csr_mstatus & 32'h000c_0122; csr_exists = ENABLE_PRIVILEGE; end
            12'h104: begin csr_old = csr_mie & csr_mideleg; csr_exists = ENABLE_PRIVILEGE; end
            12'h105: begin csr_old = csr_stvec; csr_exists = ENABLE_PRIVILEGE; end
            12'h106: begin csr_old = csr_scounteren; csr_exists = ENABLE_PRIVILEGE; end
            12'h140: begin csr_old = csr_sscratch; csr_exists = ENABLE_PRIVILEGE; end
            12'h141: begin csr_old = csr_sepc; csr_exists = ENABLE_PRIVILEGE; end
            12'h142: begin csr_old = csr_scause; csr_exists = ENABLE_PRIVILEGE; end
            12'h143: begin csr_old = csr_stval; csr_exists = ENABLE_PRIVILEGE; end
            12'h144: begin csr_old = pending_irqs & csr_mideleg; csr_exists = ENABLE_PRIVILEGE; end
            12'h180: begin csr_old = 0; csr_exists = ENABLE_PRIVILEGE && !(privilege == 1 && csr_mstatus[20]); end
            12'h302: begin csr_old = csr_medeleg; csr_exists = ENABLE_PRIVILEGE; end
            12'h303: begin csr_old = csr_mideleg; csr_exists = ENABLE_PRIVILEGE; end
            12'h306: begin csr_old = csr_mcounteren; csr_exists = ENABLE_PRIVILEGE; end
            12'h310: begin csr_old = 0; csr_exists = ENABLE_PRIVILEGE; end
            12'h320: begin csr_old = csr_mcountinhibit; csr_exists = ENABLE_PRIVILEGE; end
            12'h3a0, 12'h3a1: begin
                for (int i = 0; i < 4; i++) csr_old[i*8 +: 8] = pmpcfg[(ex_insn[20] ? 4 : 0) + i];
                csr_exists = ENABLE_PRIVILEGE;
            end
            12'h3b0, 12'h3b1, 12'h3b2, 12'h3b3, 12'h3b4, 12'h3b5, 12'h3b6, 12'h3b7: begin
                csr_old = pmpaddr[ex_insn[22:20]]; csr_exists = ENABLE_PRIVILEGE;
            end
            12'hc01, 12'hc81: begin
                csr_old = ex_insn[27] ? time_value[63:32] : time_value[31:0];
                csr_exists = ENABLE_PRIVILEGE;
            end
            12'hb00, 12'hc00: csr_old = csr_mcycle[31:0];
            12'hb80, 12'hc80: csr_old = csr_mcycle[63:32];
            12'hb02, 12'hc02: csr_old = csr_minstret[31:0];
            12'hb82, 12'hc82: csr_old = csr_minstret[63:32];
            12'hf11, 12'hf12, 12'hf13, 12'hf14: csr_old = 0;
            12'hf15, 12'h30a, 12'h31a, 12'h10a: begin csr_old = 0; csr_exists = ENABLE_PRIVILEGE; end
            default: csr_exists = 0;
        endcase
        if (ENABLE_PRIVILEGE && ex_insn[31:28] == 4'hc && privilege != 3 &&
            (!csr_mcounteren[{3'b0, ex_insn[21:20]}] ||
             (privilege == 0 && !csr_scounteren[{3'b0, ex_insn[21:20]}]))) csr_exists = 0;
        csr_operand = ex_insn[14] ? {27'b0, ex_insn[19:15]} :
            ex_rs1_value;
        csr_write_attempt = ex_insn[14:12] inside {3'b001, 3'b101} ||
            ((ex_insn[14:12] inside {3'b010, 3'b011, 3'b110, 3'b111}) &&
             ex_insn[19:15] != 0);
        case (ex_insn[13:12])
            2'b01: csr_new = csr_operand;
            2'b10: csr_new = ((ENABLE_PRIVILEGE && ex_insn[31:20] inside {12'h344, 12'h144}) ?
                (ex_insn[31:20] == 12'h144 ? csr_mip_sw & csr_mideleg : csr_mip_sw) : csr_old) | csr_operand;
            2'b11: csr_new = ((ENABLE_PRIVILEGE && ex_insn[31:20] inside {12'h344, 12'h144}) ?
                (ex_insn[31:20] == 12'h144 ? csr_mip_sw & csr_mideleg : csr_mip_sw) : csr_old) & ~csr_operand;
            default: csr_new = 0;
        endcase
        case (ex_insn[31:20])
            12'h300: begin
                csr_new = ENABLE_PRIVILEGE ? csr_new & 32'h007e_19aa : (csr_new & 32'h0000_1888) | 32'h0000_1800;
                if (ENABLE_PRIVILEGE && csr_new[12:11] == 2) csr_new[12:11] = 0;
            end
            12'h100: csr_new = (csr_mstatus & ~32'h000c_0122) | (csr_new & 32'h000c_0122);
            12'h104: csr_new = (csr_mie & ~csr_mideleg) | (csr_new & csr_mideleg);
            12'h144: csr_new = (csr_mip_sw & ~32'h2) | (csr_new & csr_mideleg & 32'h2);
            12'h344: csr_new = csr_new & 32'h222;
            12'h302: csr_new = csr_new & 32'h0000_b3ff; // defined synchronous exceptions, never M ECALL
            12'h303: csr_new = csr_new & 32'h222;
            12'h306, 12'h106: csr_new = csr_new & 7;
            12'h320: csr_new = csr_new & 5;
            12'h301: if (ENABLE_PRIVILEGE) csr_new = csr_old; // fixed RV32IMA/S/U ISA
            12'h30a, 12'h31a, 12'h10a: csr_new = 0; // no optional environment extensions
            12'h180, 12'h310: csr_new = 0; // Bare and little endian until Sv32 checkpoint
            12'h105: csr_new = {csr_new[31:2], 1'b0, csr_new[1:0] == 1};
            12'h141: csr_new = {csr_new[31:2], 2'b0};
            12'h3a0, 12'h3a1: begin
                for (int i = 0; i < 4; i++) begin
                    if (pmpcfg[(ex_insn[20] ? 4 : 0) + i][7])
                        csr_new[i*8 +: 8] = pmpcfg[(ex_insn[20] ? 4 : 0) + i];
                    else begin
                        csr_new[i*8 +: 8] = csr_new[i*8 +: 8] & 8'h9f;
                        if (csr_new[i*8 +: 2] == 2) csr_new[i*8+1] = 0;
                    end
                end
            end
            12'h3b0, 12'h3b1, 12'h3b2, 12'h3b3, 12'h3b4, 12'h3b5, 12'h3b6, 12'h3b7: begin
                if (pmpcfg[ex_insn[22:20]][7] ||
                    (ex_insn[22:20] != 7 && pmpcfg[ex_insn[22:20]+1][7] &&
                     pmpcfg[ex_insn[22:20]+1][4:3] == 1)) csr_new = csr_old;
            end
            12'h304: csr_new = csr_new & (ENABLE_PRIVILEGE ? 32'h0000_0aaa : 32'h0000_0888);
            12'h305: csr_new = {csr_new[31:2], 1'b0, (csr_new[1:0] == 2'b01)};
            12'h341: csr_new = {csr_new[31:2], 2'b0};
            default: ;
        endcase
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            csr_mstatus <= 0;
            privilege <= 3;
            csr_medeleg <= 0; csr_mideleg <= 0; csr_mip_sw <= 0;
            csr_stvec <= 0; csr_sscratch <= 0; csr_sepc <= 0; csr_scause <= 0; csr_stval <= 0;
            csr_mcounteren <= 0; csr_scounteren <= 0; csr_mcountinhibit <= 0;
            for (int i = 0; i < 8; i++) begin pmpcfg[i] <= 0; pmpaddr[i] <= 0; end
            csr_mie <= 0;
            csr_mtvec <= 0;
            csr_mscratch <= 0;
            csr_mepc <= 0;
            csr_mcause <= 0;
            csr_mtval <= 0;
            csr_mcycle <= 0;
            csr_minstret <= 0;
        end else begin
            if (!csr_mcountinhibit[0]) csr_mcycle <= csr_mcycle + 64'd1;
            if (advance) begin
                if (wb_commit.valid) begin
                    if (!wb_commit.trap && !csr_mcountinhibit[2])
                        csr_minstret <= csr_minstret + 64'd1;
                    if (wb_commit.csr_write && !wb_commit.trap) begin
                        case (wb_commit.csr_addr)
                            12'h300, 12'h100: csr_mstatus <= wb_commit.csr_data;
                            12'h104: csr_mie <= wb_commit.csr_data;
                            12'h105: csr_stvec <= wb_commit.csr_data;
                            12'h106: csr_scounteren <= wb_commit.csr_data;
                            12'h140: csr_sscratch <= wb_commit.csr_data;
                            12'h141: csr_sepc <= wb_commit.csr_data;
                            12'h142: csr_scause <= wb_commit.csr_data;
                            12'h143: csr_stval <= wb_commit.csr_data;
                            12'h144, 12'h344: csr_mip_sw <= wb_commit.csr_data;
                            12'h302: csr_medeleg <= wb_commit.csr_data;
                            12'h303: csr_mideleg <= wb_commit.csr_data;
                            12'h306: csr_mcounteren <= wb_commit.csr_data;
                            12'h320: csr_mcountinhibit <= wb_commit.csr_data;
                            12'h3a0, 12'h3a1: begin
                                for (int i = 0; i < 4; i++) begin
                                    if (!pmpcfg[(wb_commit.csr_addr[0] ? 4 : 0)+i][7]) begin
                                        pmpcfg[(wb_commit.csr_addr[0] ? 4 : 0)+i] <= wb_commit.csr_data[i*8 +: 8] & 8'h9f;
                                        // Reserved R=0/W=1 is legalized to neither permission.
                                        if (wb_commit.csr_data[i*8 +: 2] == 2)
                                            pmpcfg[(wb_commit.csr_addr[0] ? 4 : 0)+i][1] <= 0;
                                    end
                                end
                            end
                            12'h3b0, 12'h3b1, 12'h3b2, 12'h3b3, 12'h3b4, 12'h3b5, 12'h3b6, 12'h3b7: begin
                                if (!pmpcfg[wb_commit.csr_addr[2:0]][7] &&
                                    !(wb_commit.csr_addr[2:0] != 7 && pmpcfg[wb_commit.csr_addr[2:0]+1][7] &&
                                      pmpcfg[wb_commit.csr_addr[2:0]+1][4:3] == 1))
                                    pmpaddr[wb_commit.csr_addr[2:0]] <= wb_commit.csr_data;
                            end
                            12'h304: csr_mie <= wb_commit.csr_data;
                            12'h305: csr_mtvec <= wb_commit.csr_data;
                            12'h340: csr_mscratch <= wb_commit.csr_data;
                            12'h341: csr_mepc <= wb_commit.csr_data;
                            12'h342: csr_mcause <= wb_commit.csr_data;
                            12'h343: csr_mtval <= wb_commit.csr_data;
                            12'hb00: csr_mcycle[31:0] <= wb_commit.csr_data;
                            12'hb80: csr_mcycle[63:32] <= wb_commit.csr_data;
                            12'hb02: csr_minstret[31:0] <= wb_commit.csr_data;
                            12'hb82: csr_minstret[63:32] <= wb_commit.csr_data;
                            default: ;
                        endcase
                    end
                    // Without privilege, and for fatal faults, a trap records
                    // M-mode state and halts the core instead of vectoring.
                    if (wb_commit.trap && (!ENABLE_PRIVILEGE || wb_commit.fatal)) begin
                        csr_mepc <= wb_commit.pc;
                        csr_mcause <= wb_commit.cause;
                        csr_mtval <= wb_commit.tval;
                        csr_mstatus[7] <= csr_mstatus[3];
                        csr_mstatus[3] <= 0;
                        csr_mstatus[12:11] <= 2'b11;
                    end
                end
                if (xret_commit) begin
                    if (wb_commit.insn == 32'h3020_0073) begin // MRET
                        privilege <= csr_mstatus[12:11];
                        csr_mstatus[3] <= csr_mstatus[7]; csr_mstatus[7] <= 1;
                        csr_mstatus[12:11] <= 0;
                        if (csr_mstatus[12:11] != 3) csr_mstatus[17] <= 0;
                    end else begin // SRET
                        privilege <= csr_mstatus[8] ? 2'd1 : 2'd0;
                        csr_mstatus[1] <= csr_mstatus[5]; csr_mstatus[5] <= 1;
                        csr_mstatus[8] <= 0; csr_mstatus[17] <= 0;
                    end
                end
                if (trap_enter) begin
                    if (trap_to_s) begin
                        csr_sepc <= trap_pc; csr_scause <= trap_cause; csr_stval <= trap_value;
                        csr_mstatus[5] <= csr_mstatus[1]; csr_mstatus[1] <= 0;
                        csr_mstatus[8] <= privilege == 1;
                        privilege <= 1;
                    end else begin
                        csr_mepc <= trap_pc; csr_mcause <= trap_cause; csr_mtval <= trap_value;
                        csr_mstatus[7] <= csr_mstatus[3]; csr_mstatus[3] <= 0;
                        csr_mstatus[12:11] <= privilege; privilege <= 3;
                    end
                end
            end
        end
    end
endmodule
