timeunit 1ns;
timeprecision 1ps;
// Two-source, two-context SiFive-layout PLIC: source 1 UART, source 2 DMA;
// hart 0 context 0 is M-mode and context 1 is S-mode.
module plic (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        uart_irq,
    input  logic        dma_irq,
    input  logic        bus_req_valid,
    output logic        bus_req_ready,
    input  logic        bus_req_write,
    input  logic [31:0] bus_req_addr,
    input  logic [1:0]  bus_req_size,
    input  logic [31:0] bus_req_wdata,
    input  logic [3:0]  bus_req_wstrb,
    output logic        bus_rsp_valid,
    input  logic        bus_rsp_ready,
    output logic [31:0] bus_rsp_rdata,
    output logic        bus_rsp_error,
    output logic        meip_irq,
    output logic        seip_irq
);
    localparam logic [31:0] PRIORITY_UART = 32'h0c00_0004;
    localparam logic [31:0] PRIORITY_DMA  = 32'h0c00_0008;
    localparam logic [31:0] PENDING       = 32'h0c00_1000;
    localparam logic [31:0] ENABLE_M      = 32'h0c00_2000;
    localparam logic [31:0] ENABLE_S      = 32'h0c00_2080;
    localparam logic [31:0] THRESHOLD_M   = 32'h0c20_0000;
    localparam logic [31:0] CLAIM_M       = 32'h0c20_0004;
    localparam logic [31:0] THRESHOLD_S   = 32'h0c20_1000;
    localparam logic [31:0] CLAIM_S       = 32'h0c20_1004;

    logic [2:0] source_priority [2:1];
    logic [2:0] threshold_m, threshold_s;
    logic [2:1] pending, in_service, owner_s, enable_m, enable_s;
    logic [2:1] source_level;
    logic [1:0] best_m, best_s;
    logic [2:0] best_m_priority, best_s_priority;
    logic response_pending, address_valid, request_error;
    logic [31:0] read_data;

    assign source_level[1] = uart_irq;
    assign source_level[2] = dma_irq;
    assign bus_req_ready = !response_pending;
    assign bus_rsp_valid = response_pending;
    assign meip_irq = best_m != 0 && best_m_priority > threshold_m;
    assign seip_irq = best_s != 0 && best_s_priority > threshold_s;

    always_comb begin
        best_m = 0;
        best_s = 0;
        best_m_priority = 0;
        best_s_priority = 0;
        for (int id = 1; id <= 2; id++) begin
            // Claim ignores the notification threshold; priority zero is disabled.
            // Ascending scan resolves equal-priority ties in favor of the low ID.
            if (pending[id] && enable_m[id] && source_priority[id] > best_m_priority) begin
                best_m = 2'(id);
                best_m_priority = source_priority[id];
            end
            if (pending[id] && enable_s[id] && source_priority[id] > best_s_priority) begin
                best_s = 2'(id);
                best_s_priority = source_priority[id];
            end
        end
    end

    always_comb begin
        address_valid = 1'b1;
        read_data = 0;
        case (bus_req_addr)
            PRIORITY_UART: read_data = {29'b0, source_priority[1]};
            PRIORITY_DMA:  read_data = {29'b0, source_priority[2]};
            PENDING:       read_data = {29'b0, pending[2], pending[1], 1'b0};
            ENABLE_M:      read_data = {29'b0, enable_m[2], enable_m[1], 1'b0};
            ENABLE_S:      read_data = {29'b0, enable_s[2], enable_s[1], 1'b0};
            THRESHOLD_M:   read_data = {29'b0, threshold_m};
            THRESHOLD_S:   read_data = {29'b0, threshold_s};
            CLAIM_M:       read_data = {30'b0, best_m};
            CLAIM_S:       read_data = {30'b0, best_s};
            default:       address_valid = 1'b0;
        endcase
        request_error = !address_valid || bus_req_size != 2'd2 ||
                        (bus_req_write && (bus_req_wstrb != 4'b1111 ||
                                           bus_req_addr == PENDING));
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            source_priority[1] <= 0;
            source_priority[2] <= 0;
            threshold_m <= 0;
            threshold_s <= 0;
            pending <= '0;
            in_service <= '0;
            owner_s <= '0;
            enable_m <= '0;
            enable_s <= '0;
            response_pending <= 0;
            bus_rsp_rdata <= 0;
            bus_rsp_error <= 0;
        end else begin
            for (int id = 1; id <= 2; id++)
                if (source_level[id] && !pending[id] && !in_service[id])
                    pending[id] <= 1'b1;
            if (bus_rsp_valid && bus_rsp_ready)
                response_pending <= 0;
            if (bus_req_valid && bus_req_ready) begin
                response_pending <= 1;
                bus_rsp_rdata <= request_error ? 0 : read_data;
                bus_rsp_error <= request_error;
                if (!request_error) begin
                    if (bus_req_write) begin
                        case (bus_req_addr)
                            PRIORITY_UART: source_priority[1] <= bus_req_wdata[2:0];
                            PRIORITY_DMA:  source_priority[2] <= bus_req_wdata[2:0];
                            ENABLE_M:      enable_m <= bus_req_wdata[2:1];
                            ENABLE_S:      enable_s <= bus_req_wdata[2:1];
                            THRESHOLD_M:   threshold_m <= bus_req_wdata[2:0];
                            THRESHOLD_S:   threshold_s <= bus_req_wdata[2:0];
                            CLAIM_M: if (bus_req_wdata inside {32'd1, 32'd2}) begin
                                if (in_service[bus_req_wdata[1:0]] &&
                                    !owner_s[bus_req_wdata[1:0]])
                                    in_service[bus_req_wdata[1:0]] <= 0;
                            end
                            CLAIM_S: if (bus_req_wdata inside {32'd1, 32'd2}) begin
                                if (in_service[bus_req_wdata[1:0]] &&
                                    owner_s[bus_req_wdata[1:0]])
                                    in_service[bus_req_wdata[1:0]] <= 0;
                            end
                            default: ;
                        endcase
                    end else begin
                        if (bus_req_addr == CLAIM_M && best_m != 0) begin
                            pending[best_m] <= 0;
                            in_service[best_m] <= 1;
                            owner_s[best_m] <= 0;
                        end
                        if (bus_req_addr == CLAIM_S && best_s != 0) begin
                            pending[best_s] <= 0;
                            in_service[best_s] <= 1;
                            owner_s[best_s] <= 1;
                        end
                    end
                end
            end
        end
    end
endmodule
