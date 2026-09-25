// Simulation/bring-up wrapper. The zero-wait instruction/data ports are
// replaced by cache and bus interfaces in later checkpoints.
module checkpoint4_top #(
    parameter integer UART_CLOCKS_PER_BIT = 8,
    parameter integer BUTTON_STABLE_CYCLES = 3
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        manual_halt,
    input  logic        dump_button,
    output logic [31:0] imem_addr,
    input  logic [31:0] imem_rdata,
    output logic [31:0] dmem_addr,
    input  logic [31:0] dmem_rdata,
    output logic [31:0] dmem_wdata,
    output logic [3:0]  dmem_wstrb,
    output logic        uart_tx,
    (* mark_debug = "true" *) output logic        dump_busy,
    (* mark_debug = "true" *) output logic [8:0]  trace_count,
    (* mark_debug = "true" *) output logic [7:0]  trace_write_ptr,
    (* mark_debug = "true" *) output logic [7:0]  ila_pipeline,
    (* mark_debug = "true" *) output logic        retire_valid,
    (* mark_debug = "true" *) output logic [31:0] retire_pc,
    output logic [31:0] retire_insn,
    output logic [1:0]  retire_priv,
    output logic [4:0]  retire_rd,
    output logic [31:0] retire_rd_data,
    output logic [31:0] retire_mem_addr,
    output logic [3:0]  retire_mem_rmask,
    output logic [3:0]  retire_mem_wmask,
    output logic [31:0] retire_mem_wdata,
    output logic        retire_trap,
    (* mark_debug = "true" *) output logic [31:0] retire_cause,
    (* mark_debug = "true" *) output logic [31:0] retire_tval,
    output logic        done
);
    logic freeze_core;
    // This test wrapper starts directly in RAM; the board reset vector stays
    // at zero for the BRAM loader specified in the architecture contract.
    rv32_slice #(.RESET_PC(32'h8000_0000)) core (
        .clk(clk), .rst_n(rst_n), .debug_halt(manual_halt || freeze_core),
        .imem_addr(imem_addr), .imem_rdata(imem_rdata),
        .dmem_addr(dmem_addr), .dmem_rdata(dmem_rdata),
        .dmem_wdata(dmem_wdata), .dmem_wstrb(dmem_wstrb),
        .retire_valid(retire_valid), .retire_pc(retire_pc),
        .retire_insn(retire_insn), .retire_priv(retire_priv),
        .retire_rd(retire_rd), .retire_rd_data(retire_rd_data),
        .retire_mem_addr(retire_mem_addr), .retire_mem_rmask(retire_mem_rmask),
        .retire_mem_wmask(retire_mem_wmask), .retire_mem_wdata(retire_mem_wdata),
        .retire_trap(retire_trap), .retire_cause(retire_cause),
        .retire_tval(retire_tval), .done(done), .ila_pipeline(ila_pipeline)
    );
    trace_ring_uart #(.UART_CLOCKS_PER_BIT(UART_CLOCKS_PER_BIT),
                      .BUTTON_STABLE_CYCLES(BUTTON_STABLE_CYCLES)) trace (
        .clk(clk), .rst_n(rst_n), .dump_button(dump_button),
        .retire_valid(retire_valid), .retire_pc(retire_pc),
        .retire_insn(retire_insn), .retire_priv(retire_priv),
        .retire_trap(retire_trap), .retire_cause(retire_cause),
        .retire_tval(retire_tval), .uart_tx(uart_tx),
        .freeze_core(freeze_core), .dump_busy(dump_busy),
        .trace_count(trace_count), .trace_write_ptr(trace_write_ptr)
    );
endmodule
