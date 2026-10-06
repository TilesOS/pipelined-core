`timescale 1ns/1ps
// One outstanding device operation; response ownership is held until consumed.
// Future DMA/QSPI/debug apertures intentionally return DECERR in checkpoint 10.
module checkpoint10_mmio #(
    parameter int CYCLES_PER_TICK = 50,
    parameter logic [15:0] UART_DEFAULT_DIVISOR = 16'd27
) (
    input logic clk, rst_n, uart_rx, dma_irq,
    output logic [63:0] time_value,
    output logic uart_tx, msip_irq, mtip_irq, meip_irq, seip_irq,
    input axi128_pkg::axi_req_t axi_req,
    output axi128_pkg::axi_rsp_t axi_rsp
);
    logic req_valid, req_ready, req_write, rsp_valid, rsp_ready, rsp_error;
    logic [31:0] req_addr, req_wdata, rsp_rdata;
    logic [1:0] req_size;
    logic [3:0] req_wstrb;
    logic [2:0] device_req_valid, device_req_ready, device_rsp_valid, device_rsp_ready, device_error;
    logic [31:0] device_rdata [3];
    logic [1:0] selected, owner;
    logic unmapped_pending, uart_irq;
    always_comb begin
        selected = 3;
        if (req_addr[31:16] == 16'h0200) selected = 0;
        else if (req_addr[31:26] == 6'b000011) selected = 1;
        else if (req_addr[31:12] == 20'h10000) selected = 2;
        device_req_valid = 0;
        device_rsp_ready = 0;
        req_ready = !unmapped_pending;
        rsp_valid = unmapped_pending;
        rsp_rdata = 0;
        rsp_error = 0;
        if (selected != 3) begin
            device_req_valid[selected] = req_valid;
            req_ready = device_req_ready[selected];
        end
        if (owner != 3) begin
            device_rsp_ready[owner] = rsp_ready;
            rsp_valid = device_rsp_valid[owner];
            rsp_rdata = device_rdata[owner];
            rsp_error = device_error[owner];
        end
    end
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin owner <= 3; unmapped_pending <= 0; end
        else begin
            if (rsp_valid && rsp_ready) unmapped_pending <= 0;
            if (req_valid && req_ready) begin
                owner <= selected;
                if (selected == 3) unmapped_pending <= 1;
            end
        end
    end
    axi_peripheral_adapter adapter (
        .clk(clk), .rst_n(rst_n), .axi_req(axi_req), .axi_rsp(axi_rsp),
        .bus_req_valid(req_valid), .bus_req_ready(req_ready), .bus_req_write(req_write),
        .bus_req_addr(req_addr), .bus_req_size(req_size), .bus_req_wdata(req_wdata), .bus_req_wstrb(req_wstrb),
        .bus_rsp_valid(rsp_valid), .bus_rsp_ready(rsp_ready), .bus_rsp_rdata(rsp_rdata),
        .bus_rsp_error(rsp_error), .bus_rsp_decode_error(unmapped_pending)
    );
    clint #(.CYCLES_PER_TICK(CYCLES_PER_TICK)) device_0 (
        .clk(clk), .rst_n(rst_n), .time_value(time_value), .msip_irq(msip_irq), .mtip_irq(mtip_irq),
        .bus_req_valid(device_req_valid[0]), .bus_req_ready(device_req_ready[0]),
        .bus_req_write(req_write), .bus_req_addr(req_addr), .bus_req_size(req_size),
        .bus_req_wdata(req_wdata), .bus_req_wstrb(req_wstrb),
        .bus_rsp_valid(device_rsp_valid[0]), .bus_rsp_ready(device_rsp_ready[0]),
        .bus_rsp_rdata(device_rdata[0]), .bus_rsp_error(device_error[0])
    );
    plic  device_1 (
        .clk(clk), .rst_n(rst_n), .uart_irq(uart_irq), .dma_irq(dma_irq), .meip_irq(meip_irq), .seip_irq(seip_irq),
        .bus_req_valid(device_req_valid[1]), .bus_req_ready(device_req_ready[1]),
        .bus_req_write(req_write), .bus_req_addr(req_addr), .bus_req_size(req_size),
        .bus_req_wdata(req_wdata), .bus_req_wstrb(req_wstrb),
        .bus_rsp_valid(device_rsp_valid[1]), .bus_rsp_ready(device_rsp_ready[1]),
        .bus_rsp_rdata(device_rdata[1]), .bus_rsp_error(device_error[1])
    );
    uart16550 #(.DEFAULT_DIVISOR(UART_DEFAULT_DIVISOR)) device_2 (
        .clk(clk), .rst_n(rst_n), .uart_rx(uart_rx), .uart_tx(uart_tx), .irq(uart_irq),
        .bus_req_valid(device_req_valid[2]), .bus_req_ready(device_req_ready[2]),
        .bus_req_write(req_write), .bus_req_addr(req_addr), .bus_req_size(req_size),
        .bus_req_wdata(req_wdata), .bus_req_wstrb(req_wstrb),
        .bus_rsp_valid(device_rsp_valid[2]), .bus_rsp_ready(device_rsp_ready[2]),
        .bus_rsp_rdata(device_rdata[2]), .bus_rsp_error(device_error[2])
    );
endmodule
