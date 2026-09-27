`timescale 1ns/1ps
module checkpoint8_traffic_tb;
    import axi128_pkg::*;
    logic core_clk = 0;
    logic mig_clk = 0;
    logic rst_n = 0;
    logic calib_complete = 0;
    logic masters_ready;
    logic done;
    logic [31:0] baseline_write_cycles, baseline_read_cycles;
    logic [31:0] contended_write_cycles, contended_read_cycles;
    logic [31:0] dma_errors, cpu_errors, cpu_round_trips;
    logic uart_tx;
    logic [7:0] packet [33];
    axi_req4_t master_req;
    axi_rsp4_t master_rsp;
    axi_req_t dma_req, cpu_req, peripheral_req, mig_req;
    axi_rsp_t dma_rsp, cpu_rsp, peripheral_rsp, mig_rsp;
    logic [1:0] read_owner, write_owner, active;
    logic [2:0] aw_level, w_level, ar_level, b_level, r_level;
    integer core_half = 10;
    integer mig_half = 6;
    integer cycles = 0;
    initial begin
        void'($value$plusargs("core_half=%d", core_half));
        void'($value$plusargs("mig_half=%d", mig_half));
    end
    always #(core_half) core_clk = ~core_clk;
    always #(mig_half) mig_clk = ~mig_clk;
    always_comb begin
        master_req = '0;
        master_req[0] = dma_req;
        master_req[1] = cpu_req;
        dma_rsp = master_rsp[0];
        cpu_rsp = master_rsp[1];
        peripheral_rsp = '0;
    end
    checkpoint8_traffic dut (
        .clk(core_clk), .rst_n(masters_ready), .run(masters_ready),
        .dma_req(dma_req), .dma_rsp(dma_rsp),
        .cpu_req(cpu_req), .cpu_rsp(cpu_rsp), .done(done),
        .baseline_write_cycles(baseline_write_cycles),
        .baseline_read_cycles(baseline_read_cycles),
        .contended_write_cycles(contended_write_cycles),
        .contended_read_cycles(contended_read_cycles),
        .dma_errors(dma_errors), .cpu_errors(cpu_errors),
        .cpu_round_trips(cpu_round_trips)
    );
    checkpoint8_uart_report #(.CLOCKS_PER_BIT(8), .REPEAT_CYCLES(1000)) report (
        .clk(core_clk), .rst_n(masters_ready), .done(done),
        .baseline_write_cycles(baseline_write_cycles),
        .baseline_read_cycles(baseline_read_cycles),
        .contended_write_cycles(contended_write_cycles),
        .contended_read_cycles(contended_read_cycles),
        .dma_errors(dma_errors), .cpu_errors(cpu_errors),
        .cpu_round_trips(cpu_round_trips), .tx(uart_tx)
    );
    axi_subsystem subsystem (
        .core_clk(core_clk), .mig_clk(mig_clk), .rst_n(rst_n),
        .mig_calib_complete(calib_complete), .masters_ready(masters_ready),
        .master_req(master_req), .master_rsp(master_rsp),
        .peripheral_req(peripheral_req), .peripheral_rsp(peripheral_rsp),
        .mig_req(mig_req), .mig_rsp(mig_rsp),
        .read_owner_probe(read_owner), .write_owner_probe(write_owner),
        .active_probe(active), .aw_level(aw_level), .w_level(w_level),
        .ar_level(ar_level), .b_level(b_level), .r_level(r_level)
    );
    axi_test_slave #(.BYTES(262144)) ddr (
        .clk(mig_clk), .rst_n(rst_n && calib_complete),
        .req(mig_req), .rsp(mig_rsp)
    );
    always @(posedge core_clk) if (rst_n) begin
        cycles++;
        if (cycles > 2000000) $fatal(1, "checkpoint 8 traffic timed out");
    end
    task automatic receive_byte(output logic [7:0] value);
        @(negedge uart_tx);
        repeat (4) @(posedge core_clk);
        if (uart_tx !== 1'b0) $fatal(1, "bad UART start bit");
        for (int i = 0; i < 8; i++) begin
            repeat (8) @(posedge core_clk);
            value[i] = uart_tx;
        end
        repeat (8) @(posedge core_clk);
        if (uart_tx !== 1'b1) $fatal(1, "bad UART stop bit");
    endtask
    initial begin
        repeat (10) @(negedge core_clk);
        rst_n = 1;
        calib_complete = 1;
        wait (done);
        for (int i = 0; i < 33; i++) receive_byte(packet[i]);
        if (dma_errors != 0 || cpu_errors != 0)
            $fatal(1, "data/response errors: DMA=%0d CPU=%0d", dma_errors, cpu_errors);
        if (cpu_round_trips == 0 || baseline_write_cycles == 0 ||
            baseline_read_cycles == 0 || contended_write_cycles == 0 ||
            contended_read_cycles == 0)
            $fatal(1, "missing traffic or measurement");
        if ({packet[0], packet[1], packet[2], packet[3], packet[4]} !==
            {8'h44, 8'h38, 8'h42, 8'h4d, 8'h01} ||
            {packet[8], packet[7], packet[6], packet[5]} !== baseline_write_cycles ||
            {packet[12], packet[11], packet[10], packet[9]} !== baseline_read_cycles ||
            {packet[16], packet[15], packet[14], packet[13]} !== contended_write_cycles ||
            {packet[20], packet[19], packet[18], packet[17]} !== contended_read_cycles ||
            {packet[32], packet[31], packet[30], packet[29]} !== cpu_round_trips)
            $fatal(1, "UART packet did not match benchmark results");
        $display("PASS: DDR surrogate sweep: base W/R %0d/%0d cycles, contended W/R %0d/%0d cycles, CPU trips %0d",
                 baseline_write_cycles, baseline_read_cycles,
                 contended_write_cycles, contended_read_cycles, cpu_round_trips);
        $finish;
    end
endmodule
