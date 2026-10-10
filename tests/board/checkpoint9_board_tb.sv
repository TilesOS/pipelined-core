`timescale 1ns/1ps
module checkpoint9_board_tb;
    import axi128_pkg::*;
    logic core_clk = 0, mig_clk = 0, rst_n = 0, calib = 0;
    integer core_half = 10, mig_half = 6, cycles = 0;
    logic uart_tx, masters_ready, cpu_done, passed;
    logic [31:0] phase, result;
    axi_req_t req;
    axi_rsp_t rsp;
    logic [7:0] packet [61];
    bit expect_failure;
    string capture_path;
    integer capture_fd;
    initial begin
        void'($value$plusargs("core_half=%d", core_half));
        void'($value$plusargs("mig_half=%d", mig_half));
        expect_failure = $test$plusargs("expect_failure");
    end
    always #(core_half) core_clk = ~core_clk;
    always #(mig_half) mig_clk = ~mig_clk;
    checkpoint9_board_system #(.ROM_FILE("config/rom/checkpoint9_smoke.mem"),
        .UART_CLOCKS_PER_BIT(8), .REPORT_REPEAT_CYCLES(10000)) dut (
        .core_clk(core_clk), .mig_clk(mig_clk), .rst_n(rst_n), .mig_calib_complete(calib),
        .mig_req(req), .mig_rsp(rsp), .uart_tx(uart_tx), .masters_ready(masters_ready),
        .cpu_done(cpu_done), .passed(passed), .phase(phase), .result(result)
    );
    cache_test_memory memory (.clk(mig_clk), .rst_n(rst_n && calib), .req(req), .rsp(rsp));
    always @(posedge core_clk) begin
        cycles++;
        if (cycles > 6000000) $fatal(1, "board test watchdog phase=%0d pc=%h", phase, dut.last_pc);
    end
    task automatic receive_byte(output logic [7:0] value);
        @(negedge uart_tx);
        repeat (4) @(posedge core_clk);
        if (uart_tx !== 0) $fatal(1, "UART start bit");
        for (int i = 0; i < 8; i++) begin
            repeat (8) @(posedge core_clk);
            value[i] = uart_tx;
        end
        repeat (8) @(posedge core_clk);
        if (uart_tx !== 1) $fatal(1, "UART stop bit");
    endtask
    initial begin
        repeat (10) @(negedge core_clk);
        rst_n = 1;
        repeat (40) @(negedge core_clk);
        if (masters_ready || cpu_done) $fatal(1, "CPU ran before calibration");
        calib = 1;
        wait (cpu_done);
        wait (dut.traffic.state == 5);
        repeat (10) @(negedge core_clk);
        if (expect_failure) begin
            if (passed || phase != 7 || result != 32'hc9ba_0007)
                $fatal(1, "injected DMA failure not diagnosed: phase=%0d result=%h", phase, result);
        end else if (!passed) begin
            $fatal(1, "ROM test failed phase=%0d result=%h pc=%h cause=%0d tval=%h",
                   phase, result, dut.last_pc, dut.cause, dut.tval);
        end
        wait (!dut.report.sending);
        wait (dut.report.uart.ready);
        for (int i = 0; i < 61; i++) receive_byte(packet[i]);
        if ({packet[0], packet[1], packet[2], packet[3], packet[4]} !==
            {8'h43, 8'h39, 8'h53, 8'h4d, 8'h01} ||
            {packet[16], packet[15], packet[14], packet[13]} !== result)
            $fatal(1, "board UART packet mismatch");
        if ($value$plusargs("capture=%s", capture_path)) begin
            capture_fd = $fopen(capture_path, "wb");
            if (capture_fd == 0) $fatal(1, "capture open failed");
            for (int i = 0; i < 61; i++) $fwrite(capture_fd, "%c", packet[i]);
            $fclose(capture_fd);
        end
        if (!expect_failure) begin
            // Re-run after calibration loss; DDR contents survive, L1 metadata does not.
            calib = 0;
            repeat (30) @(negedge core_clk);
            if (masters_ready || cpu_done || phase != 0 || result != 0)
                $fatal(1, "calibration loss failed to reset board subsystem");
            calib = 1;
            wait (cpu_done);
            wait (dut.traffic.state == 5);
            repeat (10) @(negedge core_clk);
            if (!passed) $fatal(1, "board test failed after calibration restart");
        end
        $display("PASS: checkpoint 9 board ROM phase=%0d result=%h I/D misses=%0d/%0d writebacks=%0d DMA trips=%0d errors=%0d",
            phase, result, dut.imiss, dut.dmiss, dut.dwb, dut.dma_trips, dut.dma_errors);
        $finish;
    end
endmodule
