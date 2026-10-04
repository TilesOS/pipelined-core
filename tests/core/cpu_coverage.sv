// Simulation-only functional coverage for the zero-wait RV32IMA testbench.
// Sample at the falling edge, after retirement outputs have settled. Architectural
// operand values come from earlier successful retirements, before the current write.
module cpu_coverage (
    input logic clk, rst_n, retire_valid, retire_trap,
    input logic [31:0] retire_insn, retire_pc, retire_rd_data, retire_mem_addr,
    input logic [31:0] retire_cause,
    input logic [4:0] retire_rd,
    input logic retire_csr_write,
    input logic [7:0] ila_pipeline
);
    logic [31:0] gpr [0:31];
    integer operation, branch_result, memory_lane, divide_case, sc_result;
    integer csr_address, csr_effect, ordering, destination;
    integer stalled, redirected, faulted;
    logic [31:0] operand1, operand2;

    function automatic integer decode(input logic [31:0] insn);
        decode = -1;
        case (insn[6:0])
            7'h37: decode = 0; // LUI
            7'h17: decode = 1; // AUIPC
            7'h6f: decode = 2; // JAL
            7'h67: if (insn[14:12] == 0) decode = 3;
            7'h63: begin
                case (insn[14:12])
                    3'd0: decode = 4; // BEQ
                    3'd1: decode = 5; // BNE
                    3'd4: decode = 6; // BLT
                    3'd5: decode = 7; // BGE
                    3'd6: decode = 8; // BLTU
                    3'd7: decode = 9; // BGEU
                    default: decode = -1;
                endcase
            end
            7'h03: begin
                case (insn[14:12])
                    3'd0: decode = 10; // LB
                    3'd1: decode = 11; // LH
                    3'd2: decode = 12; // LW
                    3'd4: decode = 13; // LBU
                    3'd5: decode = 14; // LHU
                    default: decode = -1;
                endcase
            end
            7'h23: begin
                case (insn[14:12])
                    3'd0: decode = 15; // SB
                    3'd1: decode = 16; // SH
                    3'd2: decode = 17; // SW
                    default: decode = -1;
                endcase
            end
            7'h13: begin
                case (insn[14:12])
                    3'd0: decode = 18;
                    3'd2: decode = 19;
                    3'd3: decode = 20;
                    3'd4: decode = 21;
                    3'd6: decode = 22;
                    3'd7: decode = 23;
                    3'd1: if (insn[31:25] == 0) decode = 24;
                    3'd5: begin
                        if (insn[31:25] == 0) decode = 25;
                        if (insn[31:25] == 7'h20) decode = 26;
                    end
                    default: decode = -1;
                endcase
            end
            7'h33: begin
                case ({insn[31:25], insn[14:12]})
                    10'h000: decode = 27;
                    10'h001: decode = 29;
                    10'h002: decode = 30;
                    10'h003: decode = 31;
                    10'h004: decode = 32;
                    10'h005: decode = 33;
                    10'h006: decode = 35;
                    10'h007: decode = 36;
                    10'h100: decode = 28;
                    10'h105: decode = 34;
                    10'h008: decode = 39;
                    10'h009: decode = 40;
                    10'h00a: decode = 41;
                    10'h00b: decode = 42;
                    10'h00c: decode = 43;
                    10'h00d: decode = 44;
                    10'h00e: decode = 45;
                    10'h00f: decode = 46;
                    default: decode = -1;
                endcase
            end
            7'h2f: if (insn[14:12] == 2) begin
                case (insn[31:27])
                    5'd2: if (insn[24:20] == 0) decode = 47;
                    5'd3: decode = 48;
                    5'd0: decode = 49;
                    5'd1: decode = 50;
                    5'd4: decode = 51;
                    5'd8: decode = 52;
                    5'd12: decode = 53;
                    5'd16: decode = 54;
                    5'd20: decode = 55;
                    5'd24: decode = 56;
                    5'd28: decode = 57;
                    default: decode = -1;
                endcase
            end
            7'h73: begin
                case (insn[14:12])
                    3'd1: decode = 58; // CSRRW
                    3'd2: decode = 59; // CSRRS
                    3'd3: decode = 60; // CSRRC
                    3'd5: decode = 61; // CSRRWI
                    3'd6: decode = 62; // CSRRSI
                    3'd7: decode = 63; // CSRRCI
                    default: decode = -1;
                endcase
            end
            7'h0f: begin
                if (insn[14:12] == 0) decode = 37;
                if (insn == 32'h0000100f) decode = 38;
            end
            default: decode = -1;
        endcase
    endfunction

    covergroup instruction_cg;
        cp: coverpoint operation {
            bins lui = {0};
            bins auipc = {1};
            bins jal = {2};
            bins jalr = {3};
            bins beq = {4};
            bins bne = {5};
            bins blt = {6};
            bins bge = {7};
            bins bltu = {8};
            bins bgeu = {9};
            bins lb = {10};
            bins lh = {11};
            bins lw = {12};
            bins lbu = {13};
            bins lhu = {14};
            bins sb = {15};
            bins sh = {16};
            bins sw = {17};
            bins addi = {18};
            bins slti = {19};
            bins sltiu = {20};
            bins xori = {21};
            bins ori = {22};
            bins andi = {23};
            bins slli = {24};
            bins srli = {25};
            bins srai = {26};
            bins add = {27};
            bins sub = {28};
            bins sll = {29};
            bins slt = {30};
            bins sltu = {31};
            bins op_xor = {32};
            bins srl = {33};
            bins sra = {34};
            bins op_or = {35};
            bins op_and = {36};
            bins fence = {37};
            bins fence_i = {38};
            bins mul = {39};
            bins mulh = {40};
            bins mulhsu = {41};
            bins mulhu = {42};
            bins div = {43};
            bins divu = {44};
            bins rem = {45};
            bins remu = {46};
            bins lr_w = {47};
            bins sc_w = {48};
            bins amoadd_w = {49};
            bins amoswap_w = {50};
            bins amoxor_w = {51};
            bins amoor_w = {52};
            bins amoand_w = {53};
            bins amomin_w = {54};
            bins amomax_w = {55};
            bins amominu_w = {56};
            bins amomaxu_w = {57};
            bins csrrw = {58};
            bins csrrs = {59};
            bins csrrc = {60};
            bins csrrwi = {61};
            bins csrrsi = {62};
            bins csrrci = {63};
        }
    endgroup
    instruction_cg instruction_coverage = new;

    covergroup branch_cg;
        cp: coverpoint branch_result {
            bins beq_not_taken = {0};
            bins beq_taken = {1};
            bins bne_not_taken = {2};
            bins bne_taken = {3};
            bins blt_not_taken = {8};
            bins blt_taken = {9};
            bins bge_not_taken = {10};
            bins bge_taken = {11};
            bins bltu_not_taken = {12};
            bins bltu_taken = {13};
            bins bgeu_not_taken = {14};
            bins bgeu_taken = {15};
        }
    endgroup
    branch_cg branch_coverage = new;

    covergroup memory_cg;
        cp: coverpoint memory_lane {
            bins lb_lane0 = {0};
            bins lb_lane1 = {1};
            bins lb_lane2 = {2};
            bins lb_lane3 = {3};
            bins lh_lane0 = {4};
            bins lh_lane2 = {6};
            bins lw_lane0 = {8};
            bins lbu_lane0 = {16};
            bins lbu_lane1 = {17};
            bins lbu_lane2 = {18};
            bins lbu_lane3 = {19};
            bins lhu_lane0 = {20};
            bins lhu_lane2 = {22};
            bins sb_lane0 = {32};
            bins sb_lane1 = {33};
            bins sb_lane2 = {34};
            bins sb_lane3 = {35};
            bins sh_lane0 = {36};
            bins sh_lane2 = {38};
            bins sw_lane0 = {40};
        }
    endgroup
    memory_cg memory_coverage = new;

    covergroup trap_cg;
        cp: coverpoint retire_cause {
            bins instruction_misaligned = {0};
            bins instruction_access = {1};
            bins illegal_instruction = {2};
            bins breakpoint = {3};
            bins load_misaligned = {4};
            bins load_access = {5};
            bins store_misaligned = {6};
            bins store_access = {7};
            bins machine_ecall = {11};
        }
    endgroup
    trap_cg trap_coverage = new;

    covergroup divide_cg;
        cp: coverpoint divide_case {
            bins div_ordinary = {0};
            bins div_zero_divisor = {1};
            bins div_signed_overflow = {2};
            bins divu_ordinary = {3};
            bins divu_zero_divisor = {4};
            bins rem_ordinary = {6};
            bins rem_zero_divisor = {7};
            bins rem_signed_overflow = {8};
            bins remu_ordinary = {9};
            bins remu_zero_divisor = {10};
        }
    endgroup
    divide_cg divide_coverage = new;

    covergroup sc_cg;
        cp: coverpoint sc_result {
            bins success = {0};
            bins failure = {1};
        }
    endgroup
    sc_cg sc_coverage = new;

    covergroup atomic_order_cg;
        cp: coverpoint ordering {
            bins relaxed = {0};
            bins release_order = {1};
            bins acquire = {2};
            bins acquire_release = {3};
        }
    endgroup
    atomic_order_cg atomic_order_coverage = new;

    covergroup csr_address_cg;
        cp: coverpoint csr_address {
            bins mstatus = {12'h300};
            bins misa = {12'h301};
            bins mie = {12'h304};
            bins mtvec = {12'h305};
            bins mscratch = {12'h340};
            bins mepc = {12'h341};
            bins mcause = {12'h342};
            bins mtval = {12'h343};
            bins mcycle = {12'hb00};
            bins mcycleh = {12'hb80};
            bins minstret = {12'hb02};
            bins minstreth = {12'hb82};
            bins mvendorid = {12'hf11};
            bins marchid = {12'hf12};
            bins mimpid = {12'hf13};
            bins mhartid = {12'hf14};
        }
    endgroup
    csr_address_cg csr_address_coverage = new;

    covergroup csr_effect_cg;
        cp: coverpoint csr_effect {
            bins read_only = {0};
            bins write = {1};
        }
    endgroup
    csr_effect_cg csr_effect_coverage = new;

    covergroup destination_cg;
        cp: coverpoint destination {
            bins x0 = {0};
            bins nonzero = {1};
        }
    endgroup
    destination_cg destination_coverage = new;

    covergroup stall_cg;
        cp: coverpoint stalled {
            bins clear = {0};
            bins asserted = {1};
        }
    endgroup
    stall_cg stall_coverage = new;

    covergroup redirect_cg;
        cp: coverpoint redirected {
            bins clear = {0};
            bins asserted = {1};
        }
    endgroup
    redirect_cg redirect_coverage = new;

    covergroup fault_cg;
        cp: coverpoint faulted {
            bins clear = {0};
            bins asserted = {1};
        }
    endgroup
    fault_cg fault_coverage = new;

    always @(negedge clk) begin
        if (!rst_n) begin
            for (integer i = 0; i < 32; i++) gpr[i] = 0;
        end else begin
            stalled = int'(ila_pipeline[2]);
            redirected = int'(ila_pipeline[1]);
            faulted = int'(ila_pipeline[0]);
            stall_coverage.sample();
            redirect_coverage.sample();
            fault_coverage.sample();
            if (retire_valid) begin
                if (retire_trap) begin
                    trap_coverage.sample();
                end else begin
                    operation = decode(retire_insn);
                    instruction_coverage.sample();
                    operand1 = gpr[retire_insn[19:15]];
                    operand2 = gpr[retire_insn[24:20]];
                    case (retire_insn[6:0])
                        7'h63: begin
                            case (retire_insn[14:12])
                                0: branch_result = int'(operand1 == operand2);
                                1: branch_result = int'(operand1 != operand2);
                                4: branch_result = int'($signed(operand1) < $signed(operand2));
                                5: branch_result = int'($signed(operand1) >= $signed(operand2));
                                6: branch_result = int'(operand1 < operand2);
                                7: branch_result = int'(operand1 >= operand2);
                                default: branch_result = -100;
                            endcase
                            branch_result += int'(retire_insn[14:12]) * 2;
                            branch_coverage.sample();
                        end
                        7'h03, 7'h23: begin
                            memory_lane = (int'(retire_insn[14:12]) +
                                (retire_insn[6:0] == 7'h23 ? 8 : 0)) * 4 +
                                int'(retire_mem_addr[1:0]);
                            memory_coverage.sample();
                        end
                        7'h33: if (retire_insn[31:25] == 1 && retire_insn[14]) begin
                            divide_case = (int'(retire_insn[14:12]) - 4) * 3;
                            if (operand2 == 0) divide_case += 1;
                            else if (!retire_insn[12] && operand1 == 32'h80000000 &&
                                     operand2 == 32'hffffffff) divide_case += 2;
                            divide_coverage.sample();
                        end
                        7'h2f: begin
                            ordering = int'(retire_insn[26:25]);
                            atomic_order_coverage.sample();
                            if (retire_insn[31:27] == 3 && retire_insn[11:7] != 0) begin
                                sc_result = retire_rd_data == 0 ? 0 : 1;
                                sc_coverage.sample();
                            end
                        end
                        7'h73: begin
                            csr_address = int'(retire_insn[31:20]);
                            csr_effect = int'(retire_csr_write);
                            csr_address_coverage.sample();
                            csr_effect_coverage.sample();
                        end
                        default: begin end
                    endcase
                    // Only instructions that architecturally write a destination.
                    if (retire_insn[6:0] != 7'h63 && retire_insn[6:0] != 7'h23 &&
                        retire_insn[6:0] != 7'h0f && operation >= 0) begin
                        destination = retire_insn[11:7] == 0 ? 0 : 1;
                        destination_coverage.sample();
                    end
                    if (retire_rd != 0) gpr[retire_rd] = retire_rd_data;
                end
            end
        end
    end
endmodule

bind checkpoint4_top cpu_coverage coverage_monitor (.*);

// Per-instruction histories, qualified by a precise, architecturally retired trap.
// Stage means the stage occupied by the faulting instruction when the hazard held
// it; it is NOT an unrelated stage-valid flag at the eventual retirement edge.
module cpu_hazard_coverage #(parameter bit WAIT_MEMORY = 0) (
    input logic clk, rst_n, debug_halt, trap_halted, front_halted,
    input logic [4:0] stage_valid, // {WB, MEM, EX, ID, IF}
    input logic [31:0] wb_pc,
    input logic wb_trap, wb_wait, mem_wait, fence_wait, div_stall,
    input logic hazard, raw_hazard, serialize_hazard,
    input logic redirect, ex_fault, mem_access_fault, ex_result_valid,
    input logic retire_valid, retire_trap,
    input logic [31:0] retire_pc, retire_cause
);
    initial if (WAIT_MEMORY) $fatal(1, "Hazard cross model requires the zero-wait fixture");
    // Each token carries 4 hazard kinds x 5 occupied stages. Bits survive stalls,
    // transfer with that instruction, and are discarded with flushed instructions.
    logic [19:0] history [0:4];
    logic [19:0] completed_history;
    logic [31:0] completed_pc;
    integer hazard_kind, exception_kind, pipeline_stage;

    // Partitioned native three-way crosses. Verilator 5.052 supports ignore
    // bins on coverpoints but not explicit cross-bin select expressions. These
    // disjoint products enumerate the same 96 reachable tuples out of 180:
    // flow=45, RAW/IF=9, RAW/ID=6, serialization=18, divider=18.
    // RAW/serialization stall only IF/ID. Divider traps cannot occupy EX because
    // legal DIV/REM does not fault and this fixture supplies 0xffffffff on fetch
    // failure; MEM/WB drain. ECALL, EBREAK, and failed-fetch encodings have no
    // decoded GPR source, excluding RAW/ID for those three exceptions.
    covergroup flow_trap_stage_cg;
        hazard_cp: coverpoint hazard_kind {
            bins flowing = {0};
            ignore_bins outside_partition = {1, 2, 3};
        }
        exception_cp: coverpoint exception_kind {
            bins instruction_misaligned = {0};
            bins instruction_access = {1};
            bins illegal_instruction = {2};
            bins breakpoint = {3};
            bins load_misaligned = {4};
            bins load_access = {5};
            bins store_misaligned = {6};
            bins store_access = {7};
            bins machine_ecall = {11};
        }
        stage_cp: coverpoint pipeline_stage {
            bins fetch_stage = {0};
            bins decode_stage = {1};
            bins execute_stage = {2};
            bins memory_stage = {3};
            bins writeback_stage = {4};
        }
        scenario: cross hazard_cp, exception_cp, stage_cp;
    endgroup
    flow_trap_stage_cg flow_trap_stage_coverage = new;

    covergroup raw_fetch_trap_stage_cg;
        hazard_cp: coverpoint hazard_kind {
            bins raw_dependency = {1};
            ignore_bins outside_partition = {0, 2, 3};
        }
        exception_cp: coverpoint exception_kind {
            bins instruction_misaligned = {0};
            bins instruction_access = {1};
            bins illegal_instruction = {2};
            bins breakpoint = {3};
            bins load_misaligned = {4};
            bins load_access = {5};
            bins store_misaligned = {6};
            bins store_access = {7};
            bins machine_ecall = {11};
        }
        stage_cp: coverpoint pipeline_stage {
            bins fetch_stage = {0};
            ignore_bins outside_partition = {1, 2, 3, 4};
        }
        scenario: cross hazard_cp, exception_cp, stage_cp;
    endgroup
    raw_fetch_trap_stage_cg raw_fetch_trap_stage_coverage = new;

    covergroup raw_decode_trap_stage_cg;
        hazard_cp: coverpoint hazard_kind {
            bins raw_dependency = {1};
            ignore_bins outside_partition = {0, 2, 3};
        }
        exception_cp: coverpoint exception_kind {
            bins instruction_misaligned = {0};
            bins illegal_instruction = {2};
            bins load_misaligned = {4};
            bins load_access = {5};
            bins store_misaligned = {6};
            bins store_access = {7};
            ignore_bins outside_partition = {1, 3, 11};
        }
        stage_cp: coverpoint pipeline_stage {
            bins decode_stage = {1};
            ignore_bins outside_partition = {0, 2, 3, 4};
        }
        scenario: cross hazard_cp, exception_cp, stage_cp;
    endgroup
    raw_decode_trap_stage_cg raw_decode_trap_stage_coverage = new;

    covergroup serial_trap_stage_cg;
        hazard_cp: coverpoint hazard_kind {
            bins serialization = {2};
            ignore_bins outside_partition = {0, 1, 3};
        }
        exception_cp: coverpoint exception_kind {
            bins instruction_misaligned = {0};
            bins instruction_access = {1};
            bins illegal_instruction = {2};
            bins breakpoint = {3};
            bins load_misaligned = {4};
            bins load_access = {5};
            bins store_misaligned = {6};
            bins store_access = {7};
            bins machine_ecall = {11};
        }
        stage_cp: coverpoint pipeline_stage {
            bins fetch_stage = {0};
            bins decode_stage = {1};
            ignore_bins outside_partition = {2, 3, 4};
        }
        scenario: cross hazard_cp, exception_cp, stage_cp;
    endgroup
    serial_trap_stage_cg serial_trap_stage_coverage = new;

    covergroup divider_trap_stage_cg;
        hazard_cp: coverpoint hazard_kind {
            bins divider_busy = {3};
            ignore_bins outside_partition = {0, 1, 2};
        }
        exception_cp: coverpoint exception_kind {
            bins instruction_misaligned = {0};
            bins instruction_access = {1};
            bins illegal_instruction = {2};
            bins breakpoint = {3};
            bins load_misaligned = {4};
            bins load_access = {5};
            bins store_misaligned = {6};
            bins store_access = {7};
            bins machine_ecall = {11};
        }
        stage_cp: coverpoint pipeline_stage {
            bins fetch_stage = {0};
            bins decode_stage = {1};
            ignore_bins outside_partition = {2, 3, 4};
        }
        scenario: cross hazard_cp, exception_cp, stage_cp;
    endgroup
    divider_trap_stage_cg divider_trap_stage_coverage = new;

    always @(posedge clk) begin
        if (!rst_n) begin
            for (integer s = 0; s < 5; s++) history[s] = 0;
            completed_history = 0;
            completed_pc = 0;
        end else begin
            completed_history = 0;
            if (!debug_halt && !trap_halted && !wb_wait) begin
                for (integer s = 0; s < 5; s++) begin
                    if (stage_valid[s]) begin
                        if (s < 2 && div_stall) history[s][3*5+s] = 1;
                        else if (s < 2 && hazard) begin
                            if (raw_hazard) history[s][1*5+s] = 1;
                            if (serialize_hazard) history[s][2*5+s] = 1;
                        end else if (s == 2 && div_stall) history[s][3*5+s] = 1;
                        else history[s][s] = 1;
                    end
                end
                // Capture before stage transfer; the following falling edge
                // confirms that WB really generated this precise trap event.
                if (stage_valid[4] && wb_trap) begin
                    completed_history = history[4];
                    completed_pc = wb_pc;
                end
                if (mem_wait) begin
                    history[4] = 0;
                end else begin
                    history[4] = stage_valid[3] ? history[3] : 20'b0;
                    history[3] = (!mem_access_fault && ex_result_valid) ? history[2] : 20'b0;
                    if (redirect || ex_fault || mem_access_fault) begin
                        history[2] = 0;
                        history[1] = 0;
                        history[0] = 0;
                    end else if (div_stall || fence_wait) begin
                        // EX and the front end retain their instruction tokens.
                    end else if (hazard) begin
                        history[2] = 0;
                    end else begin
                        history[2] = stage_valid[1] ? history[1] : 20'b0;
                        history[1] = stage_valid[0] ? history[0] : 20'b0;
                        history[0] = 0;
                    end
                end
            end
        end
    end

    always @(negedge clk) begin
        if (rst_n && retire_valid && retire_trap) begin
            if (retire_pc != completed_pc || completed_history == 0)
                $fatal(1, "Trap history lost or associated with the wrong instruction");
            exception_kind = int'(retire_cause);
            for (integer h = 0; h < 4; h++) begin
                for (integer s = 0; s < 5; s++) begin
                    if (completed_history[h*5+s]) begin
                        // Ignored combinations are also checked at runtime. They
                        // cannot silently conceal an incorrect history or model.
                        if ((h != 0 && s >= 2) ||
                            (h == 1 && s == 1 && exception_kind inside {1, 3, 11}))
                            $fatal(1, "Observed a structurally excluded hazard/trap/stage combination");
                        hazard_kind = h;
                        pipeline_stage = s;
                        case (h)
                            0: flow_trap_stage_coverage.sample();
                            1: if (s == 0) raw_fetch_trap_stage_coverage.sample();
                               else raw_decode_trap_stage_coverage.sample();
                            2: serial_trap_stage_coverage.sample();
                            3: divider_trap_stage_coverage.sample();
                            default: $fatal(1, "Unknown hazard kind");
                        endcase
                    end
                end
            end
        end
    end
endmodule

bind rv32_slice cpu_hazard_coverage #(.WAIT_MEMORY(WAIT_MEMORY)) hazard_coverage_monitor (
    .clk(clk), .rst_n(rst_n), .debug_halt(debug_halt), .trap_halted(trap_halted),
    .front_halted(front_halted),
    .stage_valid({wb_stage.valid, mem_stage.valid, ex_stage.valid, id_stage.valid, if_stage.valid}),
    .wb_pc(wb_stage.pc), .wb_trap(wb_stage.trap),
    .wb_wait(wb_wait), .mem_wait(mem_wait), .fence_wait(fence_wait), .div_stall(div_stall),
    .hazard(hazard), .serialize_hazard(serialize_hazard),
    .raw_hazard(id_stage.valid && (
        (id_use_rs1 && id_rs1 != 0 &&
         ((ex_stage.valid && ex_rd == id_rs1 && ex_writes_rd) ||
          (mem_stage.valid && mem_stage.rd == id_rs1 && !mem_stage.trap) ||
          (wb_stage.valid && wb_stage.rd == id_rs1 && !wb_stage.trap))) ||
        (id_use_rs2 && id_rs2 != 0 &&
         ((ex_stage.valid && ex_rd == id_rs2 && ex_writes_rd) ||
          (mem_stage.valid && mem_stage.rd == id_rs2 && !mem_stage.trap) ||
          (wb_stage.valid && wb_stage.rd == id_rs2 && !wb_stage.trap))))),
    .redirect(redirect), .ex_fault(ex_fault), .mem_access_fault(mem_access_fault),
    .ex_result_valid(ex_result.valid), .retire_valid(retire_valid), .retire_trap(retire_trap),
    .retire_pc(retire_pc), .retire_cause(retire_cause)
);
