// ID-stage interlock. There is no forwarding: an instruction in ID waits for
// any older in-flight writer of its sources, and serializing instructions
// (FENCE, AMO, SYSTEM) run alone in EX/MEM/WB.
module rv32_hazard
    import rv32_pkg::*;
(
    // Only valid, insn, rd and trap are inspected.
    /* verilator lint_off UNUSEDSIGNAL */
    input  fetch_stage_t   id_stage,
    input  execute_stage_t ex_stage,
    input  result_stage_t  mem_stage,
    input  result_stage_t  wb_stage,
    /* verilator lint_on UNUSEDSIGNAL */
    output logic           serialize_hazard,
    output logic           raw_hazard,
    output logic           hazard
);
    logic [4:0] id_rs1, id_rs2, ex_rd;
    logic id_use_rs1, id_use_rs2, ex_writes_rd, id_serial, older_serial;

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
    assign id_serial = id_stage.insn[6:0] inside {7'h0f, 7'h2f, 7'h73};
    assign older_serial = (ex_stage.valid && ex_stage.insn[6:0] inside {7'h0f, 7'h2f, 7'h73}) ||
                          (mem_stage.valid && mem_stage.insn[6:0] inside {7'h0f, 7'h2f, 7'h73}) ||
                          (wb_stage.valid && wb_stage.insn[6:0] inside {7'h0f, 7'h2f, 7'h73});
    assign serialize_hazard = id_stage.valid &&
        ((id_serial && (ex_stage.valid || mem_stage.valid || wb_stage.valid)) || older_serial);
    assign raw_hazard = id_stage.valid && (
        (id_use_rs1 && id_rs1 != 0 &&
         ((ex_stage.valid && ex_rd == id_rs1 && ex_writes_rd) ||
          (mem_stage.valid && mem_stage.rd == id_rs1 && !mem_stage.trap) ||
          (wb_stage.valid && wb_stage.rd == id_rs1 && !wb_stage.trap))) ||
        (id_use_rs2 && id_rs2 != 0 &&
         ((ex_stage.valid && ex_rd == id_rs2 && ex_writes_rd) ||
          (mem_stage.valid && mem_stage.rd == id_rs2 && !mem_stage.trap) ||
          (wb_stage.valid && wb_stage.rd == id_rs2 && !wb_stage.trap))));
    assign hazard = serialize_hazard || raw_hazard;
endmodule
