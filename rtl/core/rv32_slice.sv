// RV32IMA CPU with optional checkpoint 10 M/S/U privilege. Single issue, in order, five explicit stage registers.
// WAIT_MEMORY enables blocking cache handshakes; the fixture keeps zero wait.
// This module owns the stage registers, the memory handshakes and retirement.
// rv32_pkg holds the stage records; rv32_regfile, rv32_hazard (ID),
// rv32_execute and rv32_divider (EX), rv32_mem_stage (MEM), rv32_csr
// (CSRs, privilege, interrupts, trap entry) and rv32_pmp are its parts.
module rv32_slice
    import rv32_pkg::*;
#(
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
    fetch_stage_t if_stage, id_stage;
    execute_stage_t ex_stage;
    result_stage_t mem_stage, wb_stage, ex_result, mem_result;
    // The retirement view carries only the fields needed for architectural effects.
    /* verilator lint_off UNUSEDSIGNAL */
    result_stage_t wb_commit;
    /* verilator lint_on UNUSEDSIGNAL */
    logic wb_wait, mem_wait, fence_wait;
    logic [31:0] fetch_pc, arch_pc;
    logic front_halted, trap_halted;
    logic advance, xret_commit, trap_enter;
    logic hazard;
    // Split hazard causes are observed by the functional coverage bind.
    /* verilator lint_off UNUSEDSIGNAL */
    logic serialize_hazard, raw_hazard;
    /* verilator lint_on UNUSEDSIGNAL */
    logic redirect, ex_fault, mem_access_fault;
    logic reservation_valid;
    logic [31:0] reservation_addr;
    logic [31:0] redirect_pc;
    logic [31:0] id_operand1, id_operand2;
    logic ex_is_div, div_ready, div_stall;
    logic [31:0] div_quotient, div_remainder;
    logic [31:0] csr_old, csr_new;
    logic csr_exists, csr_write_attempt;
    logic [31:0] csr_mstatus, csr_mepc, csr_sepc;
    logic [1:0] privilege, data_privilege;
    logic [7:0] pmpcfg [8];
    logic [31:0] pmpaddr [8];
    logic irq_pending, take_irq;
    logic [31:0] trap_pc, trap_cause, trap_vector;
    logic ex_pc_allowed, data_allowed, data_protection_fault;
    logic [31:0] ex_memory_addr;
    logic [1:0] ex_memory_size;
    logic ex_memory_read, ex_memory_write;
    logic fetch_allowed;

    // Architectural state advances only while not debug-halted, not stopped
    // by a fatal trap, and not waiting for WB's store to be accepted.
    assign advance = !debug_halt && !trap_halted && !wb_wait;
    assign xret_commit = ENABLE_PRIVILEGE && wb_commit.valid && !wb_commit.trap &&
        wb_commit.insn inside {32'h3020_0073, 32'h1020_0073};
    // Interrupts are taken only between instructions, with the pipeline empty.
    assign take_irq = irq_pending && !if_stage.valid && !id_stage.valid &&
        !ex_stage.valid && !mem_stage.valid && !wb_stage.valid;
    assign trap_enter = ENABLE_PRIVILEGE &&
        ((wb_commit.valid && wb_commit.trap && !wb_commit.fatal) || take_irq);

    // Fetch, the EX-stage PC and data accesses each have their own PMP check.
    rv32_pmp #(.ENABLE_PRIVILEGE(ENABLE_PRIVILEGE)) fetch_pmp (
        .pmpcfg(pmpcfg), .pmpaddr(pmpaddr),
        .addr(fetch_pc), .size(2'd2), .mode(privilege),
        .read_access(1'b0), .write_access(1'b0), .execute_access(1'b1),
        .allow(fetch_allowed)
    );
    assign imem_protection_fault = !fetch_allowed;
    rv32_pmp #(.ENABLE_PRIVILEGE(ENABLE_PRIVILEGE)) ex_pc_pmp (
        .pmpcfg(pmpcfg), .pmpaddr(pmpaddr),
        .addr(ex_stage.pc), .size(2'd2), .mode(privilege),
        .read_access(1'b0), .write_access(1'b0), .execute_access(1'b1),
        .allow(ex_pc_allowed)
    );
    rv32_pmp #(.ENABLE_PRIVILEGE(ENABLE_PRIVILEGE)) data_pmp (
        .pmpcfg(pmpcfg), .pmpaddr(pmpaddr),
        .addr(ex_memory_addr), .size(ex_memory_size), .mode(data_privilege),
        .read_access(ex_memory_read), .write_access(ex_memory_write), .execute_access(1'b0),
        .allow(data_allowed)
    );
    assign data_protection_fault = !data_allowed;

    rv32_csr #(.ENABLE_PRIVILEGE(ENABLE_PRIVILEGE)) csr (
        .clk(clk), .rst_n(rst_n),
        .msip_irq(msip_irq), .mtip_irq(mtip_irq), .meip_irq(meip_irq), .seip_irq(seip_irq),
        .time_value(time_value),
        .ex_insn(ex_stage.insn), .ex_rs1_value(ex_stage.rs1_value),
        .csr_old(csr_old), .csr_new(csr_new),
        .csr_exists(csr_exists), .csr_write_attempt(csr_write_attempt),
        .advance(advance), .wb_commit(wb_commit),
        .xret_commit(xret_commit), .trap_enter(trap_enter), .take_irq(take_irq),
        .arch_pc(arch_pc),
        .irq_pending(irq_pending), .trap_pc(trap_pc), .trap_cause(trap_cause),
        .trap_vector(trap_vector),
        .privilege(privilege), .data_privilege(data_privilege),
        .csr_mstatus(csr_mstatus), .csr_mepc(csr_mepc), .csr_sepc(csr_sepc),
        .pmpcfg(pmpcfg), .pmpaddr(pmpaddr)
    );

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

    rv32_regfile regfile (
        .clk(clk), .rst_n(rst_n),
        .rs1(id_stage.insn[19:15]), .rs2(id_stage.insn[24:20]),
        .rs1_value(id_operand1), .rs2_value(id_operand2),
        .write_enable(advance && wb_commit.valid && !wb_commit.trap),
        .rd(wb_commit.rd), .rd_value(wb_commit.result)
    );
    rv32_hazard hazard_unit (
        .id_stage(id_stage), .ex_stage(ex_stage), .mem_stage(mem_stage), .wb_stage(wb_stage),
        .serialize_hazard(serialize_hazard), .raw_hazard(raw_hazard), .hazard(hazard)
    );

    assign ex_is_div = ex_stage.valid && ex_stage.insn[6:0] == 7'h33 &&
        ex_stage.insn[31:25] == 7'h01 && ex_stage.insn[14];
    assign div_stall = ex_is_div && !div_ready;
    rv32_divider divider (
        .clk(clk), .rst_n(rst_n), .advance(advance),
        .cancel(mem_access_fault || ex_fault || redirect),
        .kill(xret_commit || trap_enter),
        .start(ex_is_div), .is_signed(!ex_stage.insn[12]),
        .dividend(ex_stage.rs1_value), .divisor(ex_stage.rs2_value),
        .ready(div_ready), .quotient(div_quotient), .remainder(div_remainder)
    );
    rv32_execute #(.WAIT_MEMORY(WAIT_MEMORY), .ENABLE_PRIVILEGE(ENABLE_PRIVILEGE)) execute (
        .ex_stage(ex_stage), .privilege(privilege),
        .csr_mstatus(csr_mstatus), .csr_mepc(csr_mepc), .csr_sepc(csr_sepc),
        .csr_old(csr_old), .csr_new(csr_new),
        .csr_exists(csr_exists), .csr_write_attempt(csr_write_attempt),
        .div_quotient(div_quotient), .div_remainder(div_remainder), .div_stall(div_stall),
        .fence_wait(fence_wait), .fence_i_ready(fence_i_ready), .fence_i_fault(fence_i_fault),
        .pc_allowed(ex_pc_allowed), .data_protection_fault(data_protection_fault),
        .ex_result(ex_result), .redirect(redirect), .redirect_pc(redirect_pc),
        .ex_memory_addr(ex_memory_addr), .ex_memory_size(ex_memory_size),
        .ex_memory_read(ex_memory_read), .ex_memory_write(ex_memory_write)
    );
    assign ex_fault = ex_result.valid && ex_result.trap;

    rv32_mem_stage #(.WAIT_MEMORY(WAIT_MEMORY)) mem (
        .mem_stage(mem_stage), .wb_stage(wb_stage),
        .dmem_rdata(dmem_rdata), .dmem_ready(dmem_ready), .dmem_fault(dmem_fault),
        .reservation_valid(reservation_valid), .reservation_addr(reservation_addr),
        .mem_result(mem_result), .mem_access_fault(mem_access_fault)
    );

    // {WB, MEM, EX, ID, IF, stall, redirect, fault}.
    assign ila_pipeline = {wb_stage.valid, mem_stage.valid, ex_stage.valid,
                           id_stage.valid, if_stage.valid,
                           (hazard || wb_wait || mem_wait || fence_wait || div_stall),
                           redirect, (ex_fault || mem_access_fault || (WAIT_MEMORY && dstore_fault))};

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            fetch_pc <= RESET_PC;
            arch_pc <= RESET_PC;
            if_stage <= '0;
            id_stage <= '0;
            ex_stage <= '0;
            mem_stage <= '0;
            wb_stage <= '0;
            front_halted <= 0;
            trap_halted <= 0;
            reservation_valid <= 0;
            reservation_addr <= 0;
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
        end else begin
            retire_valid <= 0;
            retire_csr_write <= 0;
            if (external_store_valid && reservation_valid &&
                external_store_addr[31:4] == reservation_addr[31:4] &&
                external_store_word_mask[reservation_addr[3:2]])
                reservation_valid <= 0;
            if (advance) begin
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
                    if (!wb_commit.trap) arch_pc <= wb_commit.next_pc;
                    if (wb_commit.trap && (!ENABLE_PRIVILEGE || wb_commit.fatal))
                        trap_halted <= 1;
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
                if (xret_commit) begin
                    reservation_valid <= 0;
                    fetch_pc <= wb_commit.next_pc; arch_pc <= wb_commit.next_pc;
                    if_stage <= '0; id_stage <= '0; ex_stage <= '0; mem_stage <= '0; wb_stage <= '0;
                    front_halted <= 0;
                end
                if (trap_enter) begin
                    if (take_irq) begin
                        retire_valid <= 1; retire_pc <= trap_pc; retire_insn <= 0; retire_priv <= privilege;
                        retire_rd <= 0; retire_rd_data <= 0; retire_mem_rmask <= 0; retire_mem_wmask <= 0;
                        retire_trap <= 1; retire_cause <= trap_cause; retire_tval <= 0; retire_csr_write <= 0;
                    end
                    fetch_pc <= trap_vector; arch_pc <= trap_vector;
                    if_stage <= '0; id_stage <= '0; ex_stage <= '0; mem_stage <= '0; wb_stage <= '0;
                    front_halted <= 0; reservation_valid <= 0;
                end
            end
        end
    end
endmodule
