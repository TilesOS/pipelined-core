`timescale 1ns/1ps
// Loader decode glitches must never reach the CPU/cache asynchronous reset.
module checkpoint10_cpu_reset_tb;
    logic core_clk = 0, mig_clk = 0, rst_n = 0, calibrated = 0, cpu_run = 0;
    logic masters_ready;
    always #5 core_clk = !core_clk;
    always #7 mig_clk = !mig_clk;
    checkpoint9_top #(.REGISTER_CPU_RESET(1)) dut (
        .core_clk(core_clk),
        .mig_clk(mig_clk),
        .rst_n(rst_n),
        .mig_calib_complete(calibrated),
        .cpu_run(cpu_run),
        .manual_halt(1'b0),
        .dump_button(1'b0),
        .msip_irq(1'b0),
        .mtip_irq(1'b0),
        .meip_irq(1'b0),
        .seip_irq(1'b0),
        .time_value(64'b0),
        .masters_ready(masters_ready),
        .uart_tx(),
        .atomic_lock(),
        .loader_req('0),
        .dma_req('0),
        .loader_rsp(),
        .dma_rsp(),
        .peripheral_req(),
        .mig_req(),
        .peripheral_rsp('0),
        .mig_rsp('0),
        .retire_valid(),
        .retire_priv(),
        .retire_pc(),
        .retire_insn(),
        .retire_rd(),
        .retire_rd_data(),
        .retire_mem_addr(),
        .retire_mem_wdata(),
        .retire_mem_rmask(),
        .retire_mem_wmask(),
        .retire_trap(),
        .retire_cause(),
        .retire_tval(),
        .retire_csr_write(),
        .retire_csr_addr(),
        .retire_csr_data(),
        .done(),
        .icache_misses(),
        .dcache_misses(),
        .dcache_writebacks(),
        .icache_bypasses(),
        .dcache_bypasses()
    );
    task automatic check_reset(input logic expected);
        if (dut.cpu.rst_n !== expected)
            $fatal(1, "CPU reset expected=%d actual=%d", expected, dut.cpu.rst_n);
    endtask
    initial begin
        #20; rst_n = 1; calibrated = 1;
        wait (masters_ready);
        @(negedge core_clk); #1;
        // A false completion pulse between clock edges cannot release CPU.
        cpu_run = 1; #1; check_reset(0);
        cpu_run = 0; #1; check_reset(0);
        @(posedge core_clk); #1; check_reset(0);
        @(negedge core_clk); cpu_run = 1;
        #1; check_reset(0);
        @(posedge core_clk); #1; check_reset(1);
        // A decode glitch during execution cannot assert asynchronous reset.
        @(negedge core_clk); #1;
        cpu_run = 0; #1; check_reset(1);
        cpu_run = 1; #1; check_reset(1);
        @(posedge core_clk); #1; check_reset(1);
        // An actual run withdrawal is sampled at the next core clock.
        @(negedge core_clk); cpu_run = 0;
        @(posedge core_clk); #1; check_reset(0);
        @(negedge core_clk); cpu_run = 1;
        @(posedge core_clk); #1; check_reset(1);
        // Calibration loss resets the CPU immediately when masters_ready
        // falls, and CPU release must wait for local master recovery.
        @(negedge core_clk); #1; calibrated = 0;
        wait (!masters_ready); #1; check_reset(0);
        repeat (3) begin @(posedge core_clk); #1; check_reset(0); end
        calibrated = 1;
        wait (masters_ready); #1; check_reset(0);
        @(posedge core_clk); #1; check_reset(1);
        $display("PASS: CPU reset rejects loader decode pulses, samples run changes and asserts on link loss");
        $finish;
    end
    initial begin #10000; $fatal(1, "CPU reset test watchdog"); end
endmodule
