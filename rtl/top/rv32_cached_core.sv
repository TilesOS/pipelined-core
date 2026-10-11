// Cached CPU integration. Physical addresses feed separate blocking L1s.
// Reset this module with axi_subsystem.masters_ready at the MIG boundary.
module rv32_cached_core #(
    parameter bit ENABLE_PRIVILEGE = 0,
    parameter logic [31:0] RESET_PC = 32'h0000_0000,
    parameter integer UART_CLOCKS_PER_BIT = 8,
    parameter integer BUTTON_STABLE_CYCLES = 3
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        manual_halt,
    input logic msip_irq, mtip_irq, meip_irq, seip_irq,
    input logic [63:0] time_value,
    input  logic        dump_button,
    input logic external_store_valid,
    input logic [31:0] external_store_addr,
    input logic [3:0] external_store_word_mask,
    // Other masters must stop admitting writes and finish older writes before
    // allow_atomic_read. Already admitted W/B traffic continues to drain.
    input logic allow_atomic_read,
    output logic atomic_lock,
    output axi128_pkg::axi_req_t instruction_req, data_req,
    input axi128_pkg::axi_rsp_t instruction_rsp, data_rsp,
    output logic [31:0] icache_misses, dcache_misses, dcache_writebacks,
    output logic [31:0] icache_bypasses, dcache_bypasses,
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
    output logic        retire_csr_write,
    output logic [11:0] retire_csr_addr,
    output logic [31:0] retire_csr_data,
    output logic        done
);
    import axi128_pkg::*;
    import physical_memory_pkg::*;
    logic freeze_core, halt, imem_protection_fault;
    logic [31:0] imem_addr, imem_rdata, dmem_rdata, dmem_req_addr, dmem_write_addr, dmem_wdata;
    logic [1:0] dmem_size, dmem_write_size;
    logic imem_fault, dmem_fault, imem_ready, imem_valid, imem_accept;
    logic dmem_ready, dstore_ready, dstore_fault, dmem_read_valid, dmem_read_accept, dmem_write_valid;
    logic fence_i_valid, fence_i_ready, fence_i_fault;
    logic i_busy, i_req_ready, i_rsp_valid, i_rsp_ready;
    logic [31:0] i_addr, i_data;
    logic [1:0] i_resp;
    logic d_req_ready, d_rsp_valid, d_rsp_ready, d_req_valid, d_write;
    logic [31:0] d_addr, d_data, d_wdata;
    logic [3:0] d_strb;
    logic [1:0] d_size, d_resp;
    typedef enum logic [1:0] {D_IDLE, D_READ, D_WRITE} dstate_t;
    dstate_t dstate;
    typedef enum logic [1:0] {F_IDLE, F_CLEAN, F_INVALIDATE, F_DONE} fstate_t;
    (* mark_debug = "true" *) fstate_t fstate;
    logic d_clean_done, d_clean_fault, i_invalidate_done;
    logic [31:0] d_read_addr;
    assign halt = manual_halt || freeze_core;
    assign imem_ready = imem_protection_fault || i_busy && i_rsp_valid && i_addr == imem_addr && fstate == F_IDLE;
    assign imem_rdata = i_data;
    assign imem_fault = imem_protection_fault || i_resp != AXI_OKAY;
    // Discard an outstanding wrong-path fetch, including before invalidation.
    assign i_rsp_ready = i_busy && (imem_accept || imem_protection_fault || i_addr != imem_addr || fence_i_valid || done);
    assign dmem_ready = dstate == D_READ && d_rsp_valid;
    assign dmem_rdata = d_data << (8 * d_read_addr[1:0]);
    assign dmem_fault = !accessible(dmem_req_addr, !dmem_read_valid) ||
        (dmem_ready && d_resp != AXI_OKAY);
    assign dstore_ready = dstate == D_WRITE && d_rsp_valid;
    assign dstore_fault = dstore_ready && d_resp != AXI_OKAY;
    assign d_rsp_ready = dstate == D_READ ? dmem_read_accept :
        dstate == D_WRITE && dstore_ready && !halt;
    assign d_write = dmem_write_valid;
    assign d_addr = d_write ? dmem_write_addr : dmem_req_addr;
    assign d_size = d_write ? dmem_write_size : dmem_size;
    // The core's store data uses aligned word lanes; cache requests use lanes
    // relative to the original byte address, preserving narrow MMIO accesses.
    assign d_wdata = dmem_wdata >> (8 * dmem_write_addr[1:0]);
    assign d_strb = (4'hf >> (4 - (1 << dmem_write_size)));
    assign d_req_valid = dstate == D_IDLE && fstate == F_IDLE && !fence_i_valid &&
        (dmem_write_valid || (dmem_read_valid && (!atomic_lock || allow_atomic_read)));
    assign fence_i_ready = fstate == F_DONE;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            i_busy <= 0; i_addr <= 0;
            dstate <= D_IDLE; d_read_addr <= 0;
            fstate <= F_IDLE; fence_i_fault <= 0;
        end else begin
            if (!i_busy && imem_valid && !imem_protection_fault && fstate == F_IDLE && !fence_i_valid && i_req_ready) begin
                i_busy <= 1; i_addr <= imem_addr;
            end else if (i_rsp_valid && i_rsp_ready) i_busy <= 0;
            if (d_req_valid && d_req_ready) begin
                dstate <= d_write ? D_WRITE : D_READ;
                d_read_addr <= dmem_req_addr;
            end else if (d_rsp_valid && d_rsp_ready) dstate <= D_IDLE;
            case (fstate)
                F_IDLE: if (fence_i_valid) begin fstate <= F_CLEAN; fence_i_fault <= 0; end
                F_CLEAN: if (d_clean_done) begin
                    if (d_clean_fault) begin fence_i_fault <= 1; fstate <= F_DONE; end
                    else fstate <= F_INVALIDATE;
                end
                F_INVALIDATE: if (i_invalidate_done) fstate <= F_DONE;
                F_DONE: if (!fence_i_valid) fstate <= F_IDLE;
                default: fstate <= F_IDLE;
            endcase
        end
    end
    l1_cache #(.READ_ONLY(1), .MASTER_ID(0)) icache (
        .clk(clk), .rst_n(rst_n),
        .req_valid(!i_busy && imem_valid && !imem_protection_fault && fstate == F_IDLE && !fence_i_valid),
        .req_ready(i_req_ready), .req_write(1'b0), .req_addr(imem_addr),
        .req_wdata(32'b0), .req_size(2'd2), .req_wstrb(4'b0),
        .rsp_valid(i_rsp_valid), .rsp_ready(i_rsp_ready), .rsp_rdata(i_data), .rsp_resp(i_resp),
        .clean_valid(1'b0), .invalidate_valid(fstate == F_INVALIDATE),
        .maintenance_done(i_invalidate_done), .maintenance_fault(),
        .axi_req(instruction_req), .axi_rsp(instruction_rsp),
        .miss_count(icache_misses), .writeback_count(), .bypass_count(icache_bypasses)
    );
    l1_cache #(.MASTER_ID(1)) dcache (
        .clk(clk), .rst_n(rst_n), .req_valid(d_req_valid), .req_ready(d_req_ready),
        .req_write(d_write), .req_addr(d_addr), .req_wdata(d_wdata),
        .req_size(d_size), .req_wstrb(d_strb),
        .rsp_valid(d_rsp_valid), .rsp_ready(d_rsp_ready), .rsp_rdata(d_data), .rsp_resp(d_resp),
        .clean_valid(fstate == F_CLEAN), .invalidate_valid(1'b0),
        .maintenance_done(d_clean_done), .maintenance_fault(d_clean_fault),
        .axi_req(data_req), .axi_rsp(data_rsp),
        .miss_count(dcache_misses), .writeback_count(dcache_writebacks), .bypass_count(dcache_bypasses)
    );
    rv32_slice #(.RESET_PC(RESET_PC), .WAIT_MEMORY(1), .ENABLE_PRIVILEGE(ENABLE_PRIVILEGE)) core (
        .clk(clk), .rst_n(rst_n), .debug_halt(manual_halt || freeze_core),
        .msip_irq(msip_irq), .mtip_irq(mtip_irq), .meip_irq(meip_irq), .seip_irq(seip_irq),
        .time_value(time_value), .imem_protection_fault(imem_protection_fault),
        .imem_ready(imem_ready), .imem_valid(imem_valid), .imem_accept(imem_accept),
        .dmem_ready(dmem_ready), .dstore_ready(dstore_ready), .dstore_fault(dstore_fault),
        .dmem_read_valid(dmem_read_valid), .dmem_read_accept(dmem_read_accept),
        .dmem_req_addr(dmem_req_addr), .dmem_size(dmem_size),
        .dmem_write_valid(dmem_write_valid), .dmem_write_addr(dmem_write_addr),
        .dmem_write_size(dmem_write_size), .fence_i_valid(fence_i_valid),
        .fence_i_ready(fence_i_ready), .fence_i_fault(fence_i_fault),
        .imem_addr(imem_addr), .imem_rdata(imem_rdata), .imem_fault(imem_fault),
        .dmem_addr(), .dmem_rdata(dmem_rdata), .dmem_fault(dmem_fault),
        .external_store_valid(external_store_valid),
        .external_store_addr(external_store_addr),
        .external_store_word_mask(external_store_word_mask), .atomic_memory_ready(allow_atomic_read),
        .atomic_lock(atomic_lock),
        .dmem_waddr(),
        .dmem_wdata(dmem_wdata), .dmem_wstrb(),
        .retire_valid(retire_valid), .retire_pc(retire_pc),
        .retire_insn(retire_insn), .retire_priv(retire_priv),
        .retire_rd(retire_rd), .retire_rd_data(retire_rd_data),
        .retire_mem_addr(retire_mem_addr), .retire_mem_rmask(retire_mem_rmask),
        .retire_mem_wmask(retire_mem_wmask), .retire_mem_wdata(retire_mem_wdata),
        .retire_trap(retire_trap), .retire_cause(retire_cause),
        .retire_tval(retire_tval), .retire_csr_write(retire_csr_write),
        .retire_csr_addr(retire_csr_addr), .retire_csr_data(retire_csr_data),
        .done(done), .ila_pipeline(ila_pipeline)
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
