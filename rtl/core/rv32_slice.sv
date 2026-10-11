// RV32IMA CPU with optional checkpoint 10 M/S/U privilege. Single issue, in order, five explicit stage registers.
// WAIT_MEMORY enables blocking cache handshakes; the fixture keeps zero wait.
module rv32_slice #(
    parameter logic [31:0] RESET_PC = 32'h0000_0000,
    parameter bit WAIT_MEMORY = 0,
    parameter bit ENABLE_PRIVILEGE = 0
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        debug_halt,
    input logic msip_irq, mtip_irq, meip_irq, seip_irq,
    input logic [63:0] time_value,
    output logic imem_protection_fault,
    output logic [31:0] imem_addr,
    input  logic [31:0] imem_rdata,
    input  logic        imem_fault,
    input  logic        imem_ready,
    output logic        imem_valid,
    output logic        imem_accept,
    input  logic        dmem_ready,
    input  logic        dstore_ready,
    input  logic        dstore_fault,
    output logic        dmem_read_valid,
    output logic        dmem_read_accept,
    output logic [31:0] dmem_req_addr,
    output logic [1:0]  dmem_size,
    output logic        dmem_write_valid,
    output logic [31:0] dmem_write_addr,
    output logic [1:0]  dmem_write_size,
    output logic        fence_i_valid,
    input  logic        fence_i_ready,
    input  logic        fence_i_fault,
    output logic [31:0] dmem_addr,
    input  logic [31:0] dmem_rdata,
    input  logic        dmem_fault,
    input  logic        external_store_valid,
    input  logic [31:0] external_store_addr,
    input  logic [3:0]  external_store_word_mask,
    input  logic        atomic_memory_ready,
    output logic        atomic_lock,
    output logic [31:0] dmem_waddr,
    output logic [31:0] dmem_wdata,
    output logic [3:0]  dmem_wstrb,
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
    output logic        retire_csr_write,
    output logic [11:0] retire_csr_addr,
    output logic [31:0] retire_csr_data,
    output logic        done,
    output logic [7:0]  ila_pipeline
);
    typedef struct packed {
        logic        valid;
        logic [31:0] pc;
        logic [31:0] insn;
        logic        fault;
    } fetch_stage_t;
    typedef struct packed {
        logic        valid;
        logic [31:0] pc;
        logic [31:0] insn;
        logic        fault;
        logic [31:0] rs1_value;
        logic [31:0] rs2_value;
    } execute_stage_t;
    typedef struct packed {
        logic        valid;
        logic [31:0] pc;
        logic [31:0] insn;
        logic [4:0]  rd;
        logic [31:0] result;
        logic [31:0] next_pc;
        logic [31:0] addr;
        logic [31:0] store_data;
        logic        load;
        logic        store;
        logic [3:0]  mem_mask;
        logic [1:0]  atomic_kind; // 1=LR, 2=SC, 3=AMO
        logic [4:0]  atomic_op;
        logic [31:0] atomic_operand;
        logic        csr_write;
        logic [11:0] csr_addr;
        logic [31:0] csr_data;
        logic        trap;
        logic        fatal;
        logic [31:0] cause;
        logic [31:0] tval;
    } result_stage_t;

    fetch_stage_t if_stage, id_stage;
    execute_stage_t ex_stage;
    result_stage_t mem_stage, wb_stage, ex_result, mem_result;
    // The retirement view carries only the fields needed for architectural effects.
    /* verilator lint_off UNUSEDSIGNAL */
    result_stage_t wb_commit;
    /* verilator lint_on UNUSEDSIGNAL */
    logic wb_wait, mem_wait, fence_wait;
    logic [31:0] fetch_pc;
    logic [31:0] registers [0:31];
    logic front_halted, trap_halted;
    logic hazard, redirect, ex_fault, mem_access_fault;
    logic serialize_hazard, id_serial, older_serial;
    logic reservation_valid;
    logic [31:0] reservation_addr;
    logic [31:0] redirect_pc;
    logic [4:0] id_rs1, id_rs2;
    logic id_use_rs1, id_use_rs2;
    logic [31:0] id_operand1, id_operand2;
    logic [31:0] imm_i, imm_s, imm_b, imm_u, imm_j;
    logic [31:0] merged_load_word, load_shifted;
    logic signed [63:0] mul_ss, mul_su;
    logic [63:0] mul_uu;
    logic div_active, div_ready, div_stall, ex_is_div, div_special;
    logic div_negate_quotient, div_negate_remainder;
    logic [5:0] div_count;
    logic [31:0] div_dividend, div_divisor, div_quotient;
    logic [31:0] div_remainder;
    logic [32:0] div_trial;
    logic [31:0] div_special_quotient, div_special_remainder;
    logic [31:0] div_result_quotient, div_result_remainder;
    logic [4:0]  ex_rd;
    logic        ex_writes_rd;
    logic [31:0] csr_old, csr_operand, csr_new;
    logic csr_exists, csr_write_attempt;
    logic [31:0] csr_mstatus, csr_mie, csr_mtvec, csr_mscratch;
    logic [31:0] csr_mepc, csr_mcause, csr_mtval;
    logic [63:0] csr_mcycle, csr_minstret;
    logic [1:0] privilege;
    logic [31:0] csr_medeleg, csr_mideleg, csr_mip_sw;
    logic [31:0] csr_stvec, csr_sscratch, csr_sepc, csr_scause, csr_stval;
    logic [31:0] csr_mcounteren, csr_scounteren, csr_mcountinhibit;
    logic [31:0] pending_irqs, eligible_irqs, irq_cause, arch_pc;
    logic irq_pending, take_irq, trap_to_s;
    logic [31:0] trap_pc, trap_cause, trap_value, trap_vector;
    logic [7:0] pmpcfg [8];
    logic [31:0] pmpaddr [8];
    logic [34:0] pmp_napot_mask [8];
    logic [1:0] data_privilege;
    logic data_protection_fault;
    logic [31:0] ex_memory_addr;
    logic [1:0] ex_memory_size;
    logic ex_memory_read, ex_memory_write;
    integer register_index;

    for (genvar entry = 0; entry < 8; entry++) begin : pmp_masks
        assign pmp_napot_mask[entry][2:0] = 3'b111;
        assign pmp_napot_mask[entry][34] = 1'b0;
        for (genvar bit_no = 0; bit_no < 31; bit_no++) begin : prefix_bits
            assign pmp_napot_mask[entry][bit_no+3] = &pmpaddr[entry][bit_no:0];
        end
    end

    // PMP is checked before cache lookup and before any device request.
    // The first entry overlapping any byte wins, including partial matches.
    function automatic logic pmp_allow(input logic [31:0] addr,
        input logic [1:0] size, input logic [1:0] mode,
        input logic read_access, write_access, execute_access);
        logic full_match, start_matches, end_matches;
        logic [7:0] overlaps, grants, selected;
        logic [34:0] low_addr, high_addr, first_byte, last_byte, mask;
        overlaps = 0; grants = 0; selected = 0;
        first_byte = {3'b0, addr}; last_byte = first_byte + (35'd1 << size) - 1;
        for (int i = 0; i < 8; i++) begin
            low_addr = 0; high_addr = 0; mask = 0;
            full_match = 0; start_matches = 0; end_matches = 0;
            case (pmpcfg[i][4:3])
                1: begin
                    low_addr = i == 0 ? 35'b0 : {1'b0, pmpaddr[i-1], 2'b0};
                    high_addr = {1'b0, pmpaddr[i], 2'b0};
                    overlaps[i] = low_addr < high_addr && first_byte < high_addr && last_byte >= low_addr;
                    full_match = first_byte >= low_addr && last_byte < high_addr;
                end
                2: begin
                    // NA4 spans exactly one aligned word, including an access
                    // that straddles it with neither endpoint inside it.
                    overlaps[i] = first_byte[34:2] <= {1'b0, pmpaddr[i]} &&
                                  last_byte[34:2] >= {1'b0, pmpaddr[i]};
                    full_match = first_byte[34:2] == {1'b0, pmpaddr[i]} &&
                                 last_byte[34:2] == {1'b0, pmpaddr[i]};
                end
                3: begin
                    // Constant-position prefix bits replace the serial
                    // trailing-one counter, variable shift and range adder.
                    mask = pmp_napot_mask[i];
                    low_addr = {1'b0, pmpaddr[i], 2'b0} & ~mask;
                    start_matches = (first_byte & ~mask) == low_addr;
                    end_matches = (last_byte & ~mask) == low_addr;
                    // NAPOT regions are at least eight bytes; every supported
                    // access is at most eight, so overlap hits an endpoint.
                    overlaps[i] = start_matches || end_matches;
                    full_match = start_matches && end_matches;
                end
                default: ;
            endcase
            grants[i] = full_match && ((mode == 3 && !pmpcfg[i][7]) ||
                ((!read_access || pmpcfg[i][0]) && (!write_access || pmpcfg[i][1]) &&
                 (!execute_access || pmpcfg[i][2])));
        end
        for (int i = 0; i < 8; i++)
            selected[i] = overlaps[i] && (overlaps & 8'((1 << i)-1)) == 0;
        return !ENABLE_PRIVILEGE || (mode == 3 && overlaps == 0) || |(selected & grants);
    endfunction
    assign data_privilege = privilege == 3 && csr_mstatus[17] ? csr_mstatus[12:11] : privilege;
    assign imem_protection_fault = !pmp_allow(fetch_pc, 2'd2, privilege, 0, 0, 1);
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
    assign data_protection_fault = !pmp_allow(ex_memory_addr, ex_memory_size,
        data_privilege, ex_memory_read, ex_memory_write, 0);

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
    assign take_irq = irq_pending && !if_stage.valid && !id_stage.valid &&
        !ex_stage.valid && !mem_stage.valid && !wb_stage.valid;
    assign trap_pc = take_irq ? arch_pc : wb_commit.pc;
    assign trap_cause = take_irq ? (32'h8000_0000 | irq_cause) : wb_commit.cause;
    assign trap_value = take_irq ? 0 : wb_commit.tval;
    assign trap_to_s = ENABLE_PRIVILEGE && privilege != 3 &&
        (take_irq ? csr_mideleg[irq_cause[4:0]] : csr_medeleg[wb_commit.cause[4:0]]);
    assign trap_vector = ((trap_to_s ? csr_stvec : csr_mtvec) & 32'hffff_fffc) +
        ((take_irq && (trap_to_s ? csr_stvec[0] : csr_mtvec[0])) ? irq_cause * 4 : 0);

    logic [3:0] unused_external_store_offset;
    assign unused_external_store_offset = external_store_addr[3:0];
    assign imem_addr = fetch_pc;
    assign dmem_addr = {mem_stage.addr[31:2], 2'b0};
    assign dmem_waddr = {wb_stage.addr[31:2], 2'b0};
    assign dmem_wdata = wb_stage.store_data;
    // Stores become externally visible on the same edge as retirement.
    assign dmem_wstrb = (wb_stage.valid && wb_stage.store && !debug_halt && !wb_wait &&
                        !(WAIT_MEMORY && dstore_fault)) ? wb_stage.mem_mask : 4'h0;
    assign wb_wait = WAIT_MEMORY && wb_stage.valid && wb_stage.store && !dstore_ready;
    assign mem_wait = WAIT_MEMORY && mem_stage.valid &&
        ((mem_stage.load && !dmem_ready) || (mem_stage.atomic_kind != 0 && !atomic_memory_ready));
    assign fence_i_valid = WAIT_MEMORY && ex_stage.valid && ex_stage.insn == 32'h0000_100f;
    assign fence_wait = fence_i_valid && !fence_i_ready;
    assign imem_valid = !front_halted && !trap_halted && !debug_halt && !irq_pending;
    assign imem_accept = imem_valid && (!WAIT_MEMORY || imem_ready) &&
        !wb_wait && !mem_wait && !fence_wait && !div_stall && !hazard &&
        !redirect && !ex_fault && !mem_access_fault;
    assign dmem_read_valid = mem_stage.valid && mem_stage.load && !wb_stage.valid &&
        !debug_halt && !trap_halted;
    assign dmem_read_accept = dmem_read_valid && dmem_ready && !wb_wait;
    assign dmem_req_addr = mem_stage.addr;
    assign dmem_size = mem_stage.atomic_kind != 0 ? 2'd2 : mem_stage.insn[13:12];
    assign dmem_write_valid = wb_stage.valid && wb_stage.store && !debug_halt && !trap_halted;
    assign dmem_write_addr = wb_stage.addr;
    assign dmem_write_size = wb_stage.atomic_kind != 0 ? 2'd2 : wb_stage.insn[13:12];
    always_comb begin
        wb_commit = wb_stage;
        if (WAIT_MEMORY && wb_stage.store && dstore_fault) begin
            wb_commit.trap = 1;
            wb_commit.cause = 7;
            wb_commit.tval = wb_stage.addr;
            wb_commit.rd = 0;
            wb_commit.store = 0;
            wb_commit.load = 0;
            wb_commit.mem_mask = 0;
            wb_commit.atomic_kind = 0;
        end
    end
    assign done = trap_halted;
    assign atomic_lock = (mem_stage.valid && mem_stage.atomic_kind != 0) ||
                         (wb_stage.valid && wb_stage.atomic_kind != 0);

    assign id_rs1 = id_stage.insn[19:15];
    assign id_rs2 = id_stage.insn[24:20];
    always_comb begin
        id_use_rs1 = 1'b0;
        id_use_rs2 = 1'b0;
        case (id_stage.insn[6:0])
            7'h13, 7'h03, 7'h67: id_use_rs1 = 1'b1;
            7'h33, 7'h23, 7'h63: begin
                id_use_rs1 = 1'b1;
                id_use_rs2 = 1'b1;
            end
            7'h2f: begin
                id_use_rs1 = 1'b1;
                id_use_rs2 = id_stage.insn[31:27] != 5'b00010;
            end
            7'h73: id_use_rs1 = !id_stage.insn[14];
            default: ;
        endcase
    end
    assign ex_rd = ex_stage.insn[11:7];
    assign ex_writes_rd = ex_stage.insn[6:0] inside {7'h03, 7'h13, 7'h17, 7'h2f, 7'h33, 7'h37, 7'h67, 7'h6f, 7'h73};
    assign id_operand1 = registers[id_rs1];
    assign id_operand2 = registers[id_rs2];
    assign id_serial = id_stage.insn[6:0] inside {7'h0f, 7'h2f, 7'h73};
    assign older_serial = (ex_stage.valid && ex_stage.insn[6:0] inside {7'h0f, 7'h2f, 7'h73}) ||
                          (mem_stage.valid && mem_stage.insn[6:0] inside {7'h0f, 7'h2f, 7'h73}) ||
                          (wb_stage.valid && wb_stage.insn[6:0] inside {7'h0f, 7'h2f, 7'h73});
    assign serialize_hazard = id_stage.valid &&
        ((id_serial && (ex_stage.valid || mem_stage.valid || wb_stage.valid)) || older_serial);
    assign hazard = serialize_hazard || (id_stage.valid && (
        (id_use_rs1 && id_rs1 != 0 &&
         ((ex_stage.valid && ex_rd == id_rs1 && ex_writes_rd) ||
          (mem_stage.valid && mem_stage.rd == id_rs1 && !mem_stage.trap) ||
          (wb_stage.valid && wb_stage.rd == id_rs1 && !wb_stage.trap))) ||
        (id_use_rs2 && id_rs2 != 0 &&
         ((ex_stage.valid && ex_rd == id_rs2 && ex_writes_rd) ||
          (mem_stage.valid && mem_stage.rd == id_rs2 && !mem_stage.trap) ||
          (wb_stage.valid && wb_stage.rd == id_rs2 && !wb_stage.trap)))));

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
    assign ex_is_div = ex_stage.valid && ex_stage.insn[6:0] == 7'h33 &&
        ex_stage.insn[31:25] == 7'h01 && ex_stage.insn[14];
    assign div_ready = div_active && div_count == 0;
    assign div_stall = ex_is_div && !div_ready;
    assign div_trial = {div_remainder, div_dividend[31]};
    assign div_result_quotient = div_special ? div_special_quotient :
        (div_negate_quotient ? -div_quotient : div_quotient);
    assign div_result_remainder = div_special ? div_special_remainder :
        (div_negate_remainder ? -div_remainder : div_remainder);

    always_comb begin
        csr_exists = 1;
        csr_old = 0;
        case (ex_stage.insn[31:20])
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
                for (int i = 0; i < 4; i++) csr_old[i*8 +: 8] = pmpcfg[(ex_stage.insn[20] ? 4 : 0) + i];
                csr_exists = ENABLE_PRIVILEGE;
            end
            12'h3b0, 12'h3b1, 12'h3b2, 12'h3b3, 12'h3b4, 12'h3b5, 12'h3b6, 12'h3b7: begin
                csr_old = pmpaddr[ex_stage.insn[22:20]]; csr_exists = ENABLE_PRIVILEGE;
            end
            12'hc01, 12'hc81: begin
                csr_old = ex_stage.insn[27] ? time_value[63:32] : time_value[31:0];
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
        if (ENABLE_PRIVILEGE && ex_stage.insn[31:28] == 4'hc && privilege != 3 &&
            (!csr_mcounteren[{3'b0, ex_stage.insn[21:20]}] ||
             (privilege == 0 && !csr_scounteren[{3'b0, ex_stage.insn[21:20]}]))) csr_exists = 0;
        csr_operand = ex_stage.insn[14] ? {27'b0, ex_stage.insn[19:15]} :
            ex_stage.rs1_value;
        csr_write_attempt = ex_stage.insn[14:12] inside {3'b001, 3'b101} ||
            ((ex_stage.insn[14:12] inside {3'b010, 3'b011, 3'b110, 3'b111}) &&
             ex_stage.insn[19:15] != 0);
        case (ex_stage.insn[13:12])
            2'b01: csr_new = csr_operand;
            2'b10: csr_new = ((ENABLE_PRIVILEGE && ex_stage.insn[31:20] inside {12'h344, 12'h144}) ?
                (ex_stage.insn[31:20] == 12'h144 ? csr_mip_sw & csr_mideleg : csr_mip_sw) : csr_old) | csr_operand;
            2'b11: csr_new = ((ENABLE_PRIVILEGE && ex_stage.insn[31:20] inside {12'h344, 12'h144}) ?
                (ex_stage.insn[31:20] == 12'h144 ? csr_mip_sw & csr_mideleg : csr_mip_sw) : csr_old) & ~csr_operand;
            default: csr_new = 0;
        endcase
        case (ex_stage.insn[31:20])
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
                    if (pmpcfg[(ex_stage.insn[20] ? 4 : 0) + i][7])
                        csr_new[i*8 +: 8] = pmpcfg[(ex_stage.insn[20] ? 4 : 0) + i];
                    else begin
                        csr_new[i*8 +: 8] = csr_new[i*8 +: 8] & 8'h9f;
                        if (csr_new[i*8 +: 2] == 2) csr_new[i*8+1] = 0;
                    end
                end
            end
            12'h3b0, 12'h3b1, 12'h3b2, 12'h3b3, 12'h3b4, 12'h3b5, 12'h3b6, 12'h3b7: begin
                if (pmpcfg[ex_stage.insn[22:20]][7] ||
                    (ex_stage.insn[22:20] != 7 && pmpcfg[ex_stage.insn[22:20]+1][7] &&
                     pmpcfg[ex_stage.insn[22:20]+1][4:3] == 1)) csr_new = csr_old;
            end
            12'h304: csr_new = csr_new & (ENABLE_PRIVILEGE ? 32'h0000_0aaa : 32'h0000_0888);
            12'h305: csr_new = {csr_new[31:2], 1'b0, (csr_new[1:0] == 2'b01)};
            12'h341: csr_new = {csr_new[31:2], 2'b0};
            default: ;
        endcase
    end

    always_comb begin
        ex_result = '0;
        ex_result.valid = ex_stage.valid;
        ex_result.pc = ex_stage.pc;
        ex_result.insn = ex_stage.insn;
        ex_result.next_pc = ex_stage.pc + 4;
        redirect = 1'b0;
        redirect_pc = 32'b0;
        if (ex_stage.valid) begin
            if (ex_stage.fault || !pmp_allow(ex_stage.pc, 2'd2, privilege, 0, 0, 1)) begin
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
                            3'b100, 3'b101: ex_result.result = div_result_quotient;
                            3'b110, 3'b111: ex_result.result = div_result_remainder;
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
    assign mem_access_fault = mem_stage.valid &&
        (mem_stage.load || mem_stage.store || mem_stage.atomic_kind != 0) &&
        (!WAIT_MEMORY || !mem_stage.load || dmem_ready) && dmem_fault;
    always_comb begin
        mem_result = mem_stage;
        if (mem_stage.atomic_kind == 2) begin
            mem_result.result = 1;
            if (reservation_valid && reservation_addr == mem_stage.addr) begin
                mem_result.result = 0;
                mem_result.store = 1;
                mem_result.store_data = mem_stage.atomic_operand;
            end
        end else if (mem_stage.atomic_kind == 3) begin
            mem_result.store = 1;
            case (mem_stage.atomic_op)
                5'b00000: mem_result.store_data = merged_load_word + mem_stage.atomic_operand;
                5'b00001: mem_result.store_data = mem_stage.atomic_operand;
                5'b00100: mem_result.store_data = merged_load_word ^ mem_stage.atomic_operand;
                5'b01000: mem_result.store_data = merged_load_word | mem_stage.atomic_operand;
                5'b01100: mem_result.store_data = merged_load_word & mem_stage.atomic_operand;
                5'b10000: mem_result.store_data = $signed(merged_load_word) < $signed(mem_stage.atomic_operand) ?
                    merged_load_word : mem_stage.atomic_operand;
                5'b10100: mem_result.store_data = $signed(merged_load_word) > $signed(mem_stage.atomic_operand) ?
                    merged_load_word : mem_stage.atomic_operand;
                5'b11000: mem_result.store_data = merged_load_word < mem_stage.atomic_operand ?
                    merged_load_word : mem_stage.atomic_operand;
                5'b11100: mem_result.store_data = merged_load_word > mem_stage.atomic_operand ?
                    merged_load_word : mem_stage.atomic_operand;
                default: mem_result.store_data = 0;
            endcase
        end
        if (mem_access_fault) begin
            mem_result.trap = 1;
            mem_result.cause = mem_stage.atomic_kind == 1 ||
                (mem_stage.load && mem_stage.atomic_kind == 0) ? 32'd5 : 32'd7;
            mem_result.tval = mem_stage.addr;
            mem_result.rd = 0;
            mem_result.load = 0;
            mem_result.store = 0;
            mem_result.mem_mask = 0;
            mem_result.atomic_kind = 0;
        end
    end

    always_comb begin
        merged_load_word = dmem_rdata;
        if (wb_stage.valid && wb_stage.store &&
            wb_stage.addr[31:2] == mem_stage.addr[31:2]) begin
            for (int lane = 0; lane < 4; lane = lane + 1)
                if (wb_stage.mem_mask[lane])
                    merged_load_word[8*lane +: 8] = wb_stage.store_data[8*lane +: 8];
        end
        load_shifted = merged_load_word >> (8 * mem_stage.addr[1:0]);
    end
    assign ex_fault = ex_result.valid && ex_result.trap;

    // {WB, MEM, EX, ID, IF, stall, redirect, fault}.
    assign ila_pipeline = {wb_stage.valid, mem_stage.valid, ex_stage.valid,
                           id_stage.valid, if_stage.valid,
                           (hazard || wb_wait || mem_wait || fence_wait || div_stall),
                           redirect, (ex_fault || mem_access_fault || (WAIT_MEMORY && dstore_fault))};

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            fetch_pc <= RESET_PC;
            if_stage <= '0;
            id_stage <= '0;
            ex_stage <= '0;
            mem_stage <= '0;
            wb_stage <= '0;
            front_halted <= 0;
            trap_halted <= 0;
            reservation_valid <= 0;
            reservation_addr <= 0;
            csr_mstatus <= 0;
            privilege <= 3; arch_pc <= RESET_PC;
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
            div_active <= 0;
            div_count <= 0;
            div_dividend <= 0;
            div_divisor <= 0;
            div_quotient <= 0;
            div_remainder <= 0;
            div_negate_quotient <= 0;
            div_negate_remainder <= 0;
            div_special <= 0;
            div_special_quotient <= 0;
            div_special_remainder <= 0;
            retire_valid <= 0;
            retire_pc <= 0;
            retire_insn <= 0;
            retire_priv <= 2'd3;
            retire_rd <= 0;
            retire_rd_data <= 0;
            retire_mem_addr <= 0;
            retire_mem_rmask <= 0;
            retire_mem_wmask <= 0;
            retire_mem_wdata <= 0;
            retire_trap <= 0;
            retire_cause <= 0;
            retire_tval <= 0;
            retire_csr_write <= 0;
            retire_csr_addr <= 0;
            retire_csr_data <= 0;
            for (register_index = 0; register_index < 32; register_index = register_index + 1)
                registers[register_index] <= 0;
        end else begin
            retire_valid <= 0;
            retire_csr_write <= 0;
            if (!csr_mcountinhibit[0]) csr_mcycle <= csr_mcycle + 64'd1;
            if (external_store_valid && reservation_valid &&
                external_store_addr[31:4] == reservation_addr[31:4] &&
                external_store_word_mask[reservation_addr[3:2]])
                reservation_valid <= 0;
            if (!debug_halt && !trap_halted && !wb_wait) begin
                if (mem_access_fault || ex_fault || redirect || div_ready) begin
                    div_active <= 0;
                end else if (ex_is_div && !div_active) begin
                    div_active <= 1;
                    div_special <= ex_stage.rs2_value == 0 ||
                        (!ex_stage.insn[12] && ex_stage.rs1_value == 32'h8000_0000 &&
                         ex_stage.rs2_value == 32'hffff_ffff);
                    div_count <= (ex_stage.rs2_value == 0 ||
                        (!ex_stage.insn[12] && ex_stage.rs1_value == 32'h8000_0000 &&
                         ex_stage.rs2_value == 32'hffff_ffff)) ? 6'd0 : 6'd32;
                    div_special_quotient <= ex_stage.rs2_value == 0 ?
                        32'hffff_ffff : 32'h8000_0000;
                    div_special_remainder <= ex_stage.rs2_value == 0 ?
                        ex_stage.rs1_value : 32'b0;
                    div_negate_quotient <= !ex_stage.insn[12] &&
                        (ex_stage.rs1_value[31] ^ ex_stage.rs2_value[31]);
                    div_negate_remainder <= !ex_stage.insn[12] && ex_stage.rs1_value[31];
                    div_dividend <= (!ex_stage.insn[12] && ex_stage.rs1_value[31]) ?
                        -ex_stage.rs1_value : ex_stage.rs1_value;
                    div_divisor <= (!ex_stage.insn[12] && ex_stage.rs2_value[31]) ?
                        -ex_stage.rs2_value : ex_stage.rs2_value;
                    div_quotient <= 0;
                    div_remainder <= 0;
                end else if (div_active && div_count != 0) begin
                    div_count <= div_count - 6'd1;
                    div_dividend <= {div_dividend[30:0], 1'b0};
                    if (div_trial >= {1'b0, div_divisor}) begin
                        div_remainder <= div_trial[31:0] - div_divisor;
                        div_quotient <= {div_quotient[30:0], 1'b1};
                    end else begin
                        div_remainder <= div_trial[31:0];
                        div_quotient <= {div_quotient[30:0], 1'b0};
                    end
                end
                if (wb_commit.valid) begin
                    retire_valid <= 1;
                    retire_pc <= wb_commit.pc;
                    retire_insn <= wb_commit.insn;
                    retire_priv <= privilege;
                    retire_rd <= wb_commit.rd;
                    retire_rd_data <= wb_commit.result;
                    retire_mem_addr <= wb_commit.addr;
                    retire_mem_rmask <= wb_commit.load ? wb_commit.mem_mask : 4'h0;
                    retire_mem_wmask <= wb_commit.store ? wb_commit.mem_mask : 4'h0;
                    retire_mem_wdata <= wb_commit.store_data;
                    retire_trap <= wb_commit.trap;
                    retire_cause <= wb_commit.cause;
                    retire_tval <= wb_commit.tval;
                    retire_csr_write <= wb_commit.csr_write;
                    retire_csr_addr <= wb_commit.csr_addr;
                    retire_csr_data <= wb_commit.csr_data;
                    if (wb_commit.rd != 0 && !wb_commit.trap)
                        registers[wb_commit.rd] <= wb_commit.result;
                    if (!wb_commit.trap) arch_pc <= wb_commit.next_pc;
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
                    if (wb_commit.trap && (!ENABLE_PRIVILEGE || wb_commit.fatal)) begin
                        trap_halted <= !ENABLE_PRIVILEGE || wb_commit.fatal;
                        csr_mepc <= wb_commit.pc;
                        csr_mcause <= wb_commit.cause;
                        csr_mtval <= wb_commit.tval;
                        csr_mstatus[7] <= csr_mstatus[3];
                        csr_mstatus[3] <= 0;
                        csr_mstatus[12:11] <= 2'b11;
                    end
                    if (wb_commit.trap || wb_commit.atomic_kind == 2 ||
                        (wb_commit.store && reservation_valid &&
                         wb_commit.addr[31:2] == reservation_addr[31:2]))
                        reservation_valid <= 0;
                    if (wb_commit.atomic_kind == 1 && !wb_commit.trap) begin
                        reservation_valid <= 1;
                        reservation_addr <= wb_commit.addr;
                    end
                end
                if (mem_wait) begin
                    wb_stage <= '0;
                end else begin
                    wb_stage <= mem_result;
                    // A younger load in MEM sees an older store committing from WB
                    // on this edge, even with a synchronous memory implementation.
                    if (mem_stage.load && !mem_access_fault) begin
                        case (mem_stage.insn[14:12])
                            3'b000: wb_stage.result <= {{24{load_shifted[7]}}, load_shifted[7:0]};
                            3'b001: wb_stage.result <= {{16{load_shifted[15]}}, load_shifted[15:0]};
                            3'b010: wb_stage.result <= load_shifted;
                            3'b100: wb_stage.result <= {24'b0, load_shifted[7:0]};
                            3'b101: wb_stage.result <= {16'b0, load_shifted[15:0]};
                            default: wb_stage.result <= 0;
                        endcase
                    end else wb_stage.result <= mem_result.result;
                    mem_stage <= mem_access_fault ? '0 : ex_result;
                    if (redirect || ex_fault || mem_access_fault) begin
                        ex_stage <= '0;
                        id_stage <= '0;
                        if_stage <= '0;
                        if (redirect && !mem_access_fault) fetch_pc <= redirect_pc;
                        if (ex_fault || mem_access_fault) front_halted <= 1;
                    end else if (div_stall || fence_wait) begin
                        // Drain older stages while holding DIV/REM and the front end.
                    end else if (hazard) begin
                        ex_stage <= '0;
                    end else begin
                        ex_stage.valid <= id_stage.valid;
                        ex_stage.pc <= id_stage.pc;
                        ex_stage.insn <= id_stage.insn;
                        ex_stage.fault <= id_stage.fault;
                        ex_stage.rs1_value <= id_operand1;
                        ex_stage.rs2_value <= id_operand2;
                        id_stage <= if_stage;
                        if (front_halted || irq_pending || (WAIT_MEMORY && !imem_ready)) begin
                            if_stage <= '0;
                        end else begin
                            if_stage.valid <= 1;
                            if_stage.pc <= fetch_pc;
                            if_stage.insn <= imem_rdata;
                            if_stage.fault <= imem_fault || imem_protection_fault;
                            fetch_pc <= fetch_pc + 32'd4;
                        end
                    end
                end // MEM wait: hold MEM and younger stages, drain WB once.
                if (ENABLE_PRIVILEGE && wb_commit.valid && !wb_commit.trap &&
                    wb_commit.insn inside {32'h3020_0073, 32'h1020_0073}) begin
                    if (wb_commit.insn == 32'h3020_0073) begin
                        privilege <= csr_mstatus[12:11];
                        csr_mstatus[3] <= csr_mstatus[7]; csr_mstatus[7] <= 1;
                        csr_mstatus[12:11] <= 0;
                        if (csr_mstatus[12:11] != 3) csr_mstatus[17] <= 0;
                    end else begin
                        privilege <= csr_mstatus[8] ? 2'd1 : 2'd0;
                        csr_mstatus[1] <= csr_mstatus[5]; csr_mstatus[5] <= 1;
                        csr_mstatus[8] <= 0; csr_mstatus[17] <= 0;
                    end
                    reservation_valid <= 0;
                    fetch_pc <= wb_commit.next_pc; arch_pc <= wb_commit.next_pc;
                    if_stage <= '0; id_stage <= '0; ex_stage <= '0; mem_stage <= '0; wb_stage <= '0;
                    front_halted <= 0; div_active <= 0;
                end
                if (ENABLE_PRIVILEGE && ((wb_commit.valid && wb_commit.trap && !wb_commit.fatal) || take_irq)) begin
                    if (take_irq) begin
                        retire_valid <= 1; retire_pc <= trap_pc; retire_insn <= 0; retire_priv <= privilege;
                        retire_rd <= 0; retire_rd_data <= 0; retire_mem_rmask <= 0; retire_mem_wmask <= 0;
                        retire_trap <= 1; retire_cause <= trap_cause; retire_tval <= 0; retire_csr_write <= 0;
                    end
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
                    fetch_pc <= trap_vector; arch_pc <= trap_vector;
                    if_stage <= '0; id_stage <= '0; ex_stage <= '0; mem_stage <= '0; wb_stage <= '0;
                    front_halted <= 0; reservation_valid <= 0; div_active <= 0;
                end
            end
        end
    end
endmodule
