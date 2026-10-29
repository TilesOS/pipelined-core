// Pipeline stage records shared by the rv32 core modules.
package rv32_pkg;
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
endpackage
