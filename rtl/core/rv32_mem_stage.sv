// MEM stage: data access faults, SC/AMO store values, store-to-load
// forwarding from WB, and load alignment/extension. Produces the record MEM
// hands to WB.
module rv32_mem_stage
    import rv32_pkg::*;
#(
    parameter bit WAIT_MEMORY = 0
) (
    input  result_stage_t mem_stage,
    // Only the store fields are inspected for forwarding.
    /* verilator lint_off UNUSEDSIGNAL */
    input  result_stage_t wb_stage,
    /* verilator lint_on UNUSEDSIGNAL */
    input  logic [31:0]   dmem_rdata,
    input  logic          dmem_ready,
    input  logic          dmem_fault,
    input  logic          reservation_valid,
    input  logic [31:0]   reservation_addr,
    output result_stage_t mem_result,
    output logic          mem_access_fault
);
    logic [31:0] merged_load_word, load_shifted;

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
        // A younger load in MEM sees an older store committing from WB
        // on this edge, even with a synchronous memory implementation.
        if (mem_stage.load && !mem_access_fault) begin
            case (mem_stage.insn[14:12])
                3'b000: mem_result.result = {{24{load_shifted[7]}}, load_shifted[7:0]};
                3'b001: mem_result.result = {{16{load_shifted[15]}}, load_shifted[15:0]};
                3'b010: mem_result.result = load_shifted;
                3'b100: mem_result.result = {24'b0, load_shifted[7:0]};
                3'b101: mem_result.result = {16'b0, load_shifted[15:0]};
                default: mem_result.result = 0;
            endcase
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
endmodule
