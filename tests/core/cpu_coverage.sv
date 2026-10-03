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
