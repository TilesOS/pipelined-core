// RV32I CPU slice. Single issue, in order, five explicit stage registers.
// Memory is a zero-wait test interface until the cache/AXI checkpoints.
module rv32_slice #(
    parameter logic [31:0] RESET_PC = 32'h0000_0000
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        debug_halt,
    output logic [31:0] imem_addr,
    input  logic [31:0] imem_rdata,
    input  logic        imem_fault,
    output logic [31:0] dmem_addr,
    input  logic [31:0] dmem_rdata,
    input  logic        dmem_fault,
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
        logic [31:0] addr;
        logic [31:0] store_data;
        logic        load;
        logic        store;
        logic [3:0]  mem_mask;
        logic        trap;
        logic [31:0] cause;
        logic [31:0] tval;
    } result_stage_t;

    fetch_stage_t if_stage, id_stage;
    execute_stage_t ex_stage;
    result_stage_t mem_stage, wb_stage, ex_result, mem_result;
    logic [31:0] fetch_pc;
    logic [31:0] registers [0:31];
    logic front_halted, trap_halted;
    logic hazard, redirect, ex_fault, mem_access_fault;
    logic [31:0] redirect_pc;
    logic [4:0] id_rs1, id_rs2;
    logic id_use_rs1, id_use_rs2;
    logic [31:0] id_operand1, id_operand2;
    logic [31:0] imm_i, imm_s, imm_b, imm_u, imm_j;
    logic [31:0] merged_load_word, load_shifted;
    logic [4:0]  ex_rd;
    logic        ex_writes_rd;
    integer register_index;

    assign imem_addr = fetch_pc;
    assign dmem_addr = {mem_stage.addr[31:2], 2'b0};
    assign dmem_waddr = {wb_stage.addr[31:2], 2'b0};
    assign dmem_wdata = wb_stage.store_data;
    // Stores become externally visible on the same edge as retirement.
    assign dmem_wstrb = (wb_stage.valid && wb_stage.store && !debug_halt) ? wb_stage.mem_mask : 4'h0;
    assign done = trap_halted;

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
            default: ;
        endcase
    end
    assign ex_rd = ex_stage.insn[11:7];
    assign ex_writes_rd = ex_stage.insn[6:0] inside {7'h03, 7'h13, 7'h17, 7'h33, 7'h37, 7'h67, 7'h6f};
    assign id_operand1 = registers[id_rs1];
    assign id_operand2 = registers[id_rs2];
    assign hazard = id_stage.valid && (
        (id_use_rs1 && id_rs1 != 0 &&
         ((ex_stage.valid && ex_rd == id_rs1 && ex_writes_rd) ||
          (mem_stage.valid && mem_stage.rd == id_rs1 && !mem_stage.trap) ||
          (wb_stage.valid && wb_stage.rd == id_rs1 && !wb_stage.trap))) ||
        (id_use_rs2 && id_rs2 != 0 &&
         ((ex_stage.valid && ex_rd == id_rs2 && ex_writes_rd) ||
          (mem_stage.valid && mem_stage.rd == id_rs2 && !mem_stage.trap) ||
          (wb_stage.valid && wb_stage.rd == id_rs2 && !wb_stage.trap))));

    assign imm_i = {{20{ex_stage.insn[31]}}, ex_stage.insn[31:20]};
    assign imm_s = {{20{ex_stage.insn[31]}}, ex_stage.insn[31:25], ex_stage.insn[11:7]};
    assign imm_b = {{19{ex_stage.insn[31]}}, ex_stage.insn[31], ex_stage.insn[7],
                    ex_stage.insn[30:25], ex_stage.insn[11:8], 1'b0};
    assign imm_u = {ex_stage.insn[31:12], 12'b0};
    assign imm_j = {{11{ex_stage.insn[31]}}, ex_stage.insn[31], ex_stage.insn[19:12],
                    ex_stage.insn[20], ex_stage.insn[30:21], 1'b0};

    always_comb begin
        ex_result = '0;
        ex_result.valid = ex_stage.valid;
        ex_result.pc = ex_stage.pc;
        ex_result.insn = ex_stage.insn;
        redirect = 1'b0;
        redirect_pc = 32'b0;
        if (ex_stage.valid) begin
            if (ex_stage.fault) begin
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
                    if (ex_stage.insn[31:25] == 0) begin
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
                    ex_result.addr = ex_stage.rs1_value +
                        (ex_stage.insn[6:0] == 7'h03 ? imm_i : imm_s);
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
                7'h0f: begin // FENCE; no outstanding memory in this zero-wait slice
                    if (ex_stage.insn[14:12] != 0 || ex_rd != 0 || ex_stage.insn[19:15] != 0 ||
                        ex_stage.insn[31:28] != 0) ex_result.trap = 1;
                end
                7'h73: begin
                    if (ex_stage.insn == 32'h0000_0073) begin
                        ex_result.trap = 1;
                        ex_result.cause = 11; // M-mode ECALL
                    end else if (ex_stage.insn == 32'h0010_0073) begin
                        ex_result.trap = 1;
                        ex_result.cause = 3; // EBREAK
                        ex_result.tval = ex_stage.pc;
                    end else ex_result.trap = 1;
                end
                default: ex_result.trap = 1;
            endcase
            if (redirect && redirect_pc[1:0] != 0) begin
                redirect = 0;
                ex_result.trap = 1;
                ex_result.cause = 0;
                ex_result.tval = redirect_pc;
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
            end
        end
    end
    assign mem_access_fault = mem_stage.valid &&
        (mem_stage.load || mem_stage.store) && dmem_fault;
    always_comb begin
        mem_result = mem_stage;
        if (mem_access_fault) begin
            mem_result.trap = 1;
            mem_result.cause = mem_stage.load ? 32'd5 : 32'd7;
            mem_result.tval = mem_stage.addr;
            mem_result.rd = 0;
            mem_result.load = 0;
            mem_result.store = 0;
            mem_result.mem_mask = 0;
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

    // {WB, MEM, EX, ID, IF, decode stall, redirect, fault}.
    assign ila_pipeline = {wb_stage.valid, mem_stage.valid, ex_stage.valid,
                           id_stage.valid, if_stage.valid, hazard, redirect, ex_fault};

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
            for (register_index = 0; register_index < 32; register_index = register_index + 1)
                registers[register_index] <= 0;
        end else begin
            retire_valid <= 0;
            if (!debug_halt && !trap_halted) begin
                if (wb_stage.valid) begin
                    retire_valid <= 1;
                    retire_pc <= wb_stage.pc;
                    retire_insn <= wb_stage.insn;
                    retire_priv <= 2'd3;
                    retire_rd <= wb_stage.rd;
                    retire_rd_data <= wb_stage.result;
                    retire_mem_addr <= wb_stage.addr;
                    retire_mem_rmask <= wb_stage.load ? wb_stage.mem_mask : 4'h0;
                    retire_mem_wmask <= wb_stage.store ? wb_stage.mem_mask : 4'h0;
                    retire_mem_wdata <= wb_stage.store_data;
                    retire_trap <= wb_stage.trap;
                    retire_cause <= wb_stage.cause;
                    retire_tval <= wb_stage.tval;
                    if (wb_stage.rd != 0 && !wb_stage.trap)
                        registers[wb_stage.rd] <= wb_stage.result;
                    if (wb_stage.trap)
                        trap_halted <= 1;
                end
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
                end else wb_stage.result <= mem_stage.result;
                mem_stage <= mem_access_fault ? '0 : ex_result;
                if (redirect || ex_fault || mem_access_fault) begin
                    ex_stage <= '0;
                    id_stage <= '0;
                    if_stage <= '0;
                    if (redirect && !mem_access_fault) fetch_pc <= redirect_pc;
                    if (ex_fault || mem_access_fault) front_halted <= 1;
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
                    if (front_halted) begin
                        if_stage <= '0;
                    end else begin
                        if_stage.valid <= 1;
                        if_stage.pc <= fetch_pc;
                        if_stage.insn <= imem_rdata;
                        if_stage.fault <= imem_fault;
                        fetch_pc <= fetch_pc + 32'd4;
                    end
                end
            end
        end
    end
endmodule
