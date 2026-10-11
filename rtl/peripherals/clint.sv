timeunit 1ns;
timeprecision 1ps;
// Single-hart CLINT on the peripheral adapter's exact-address 32-bit port.
// A 50 MHz core clock with the default divider produces a 1 MHz mtime tick.
module clint #(
    parameter int CYCLES_PER_TICK = 50
) (
    input  logic        clk,
    input  logic        rst_n,
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
    output logic [63:0] time_value,
    output logic        msip_irq,
    output logic        mtip_irq
);
    localparam logic [31:0] MSIP_ADDR       = 32'h0200_0000;
    localparam logic [31:0] MTIMECMP_LO_ADDR = 32'h0200_4000;
    localparam logic [31:0] MTIMECMP_HI_ADDR = 32'h0200_4004;
    localparam logic [31:0] MTIME_LO_ADDR    = 32'h0200_bff8;
    localparam logic [31:0] MTIME_HI_ADDR    = 32'h0200_bffc;
    localparam int DIV_WIDTH = CYCLES_PER_TICK > 1 ? $clog2(CYCLES_PER_TICK) : 1;

    logic [DIV_WIDTH-1:0] tick_count;
    logic [63:0] mtime, mtimecmp, next_mtime;
    logic msip, response_pending;
    logic [31:0] read_data;
    logic address_valid, request_error, tick;

    assign time_value = mtime;
    assign tick = tick_count == DIV_WIDTH'(CYCLES_PER_TICK - 1);
    assign bus_req_ready = !response_pending;
    assign bus_rsp_valid = response_pending;
    assign msip_irq = msip;
    assign mtip_irq = mtime >= mtimecmp;

    always_comb begin
        address_valid = 1'b1;
        read_data = 0;
        case (bus_req_addr)
            MSIP_ADDR:        read_data = {31'b0, msip};
            MTIMECMP_LO_ADDR: read_data = mtimecmp[31:0];
            MTIMECMP_HI_ADDR: read_data = mtimecmp[63:32];
            MTIME_LO_ADDR:    read_data = mtime[31:0];
            MTIME_HI_ADDR:    read_data = mtime[63:32];
            default:         address_valid = 1'b0;
        endcase
        request_error = !address_valid || bus_req_size != 2'd2 ||
                        (bus_req_write && bus_req_wstrb != 4'b1111);
        next_mtime = mtime + {63'b0, tick};
        if (bus_req_valid && bus_req_ready && bus_req_write && !request_error) begin
            case (bus_req_addr)
                MTIME_LO_ADDR: next_mtime[31:0] = bus_req_wdata;
                MTIME_HI_ADDR: next_mtime[63:32] = bus_req_wdata;
                default: ;
            endcase
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tick_count <= '0;
            mtime <= '0;
            mtimecmp <= '1;
            msip <= 1'b0;
            response_pending <= 1'b0;
            bus_rsp_rdata <= '0;
            bus_rsp_error <= 1'b0;
        end else begin
            tick_count <= tick ? '0 : tick_count + 1'b1;
            mtime <= next_mtime;
            if (bus_rsp_valid && bus_rsp_ready)
                response_pending <= 1'b0;
            if (bus_req_valid && bus_req_ready) begin
                response_pending <= 1'b1;
                bus_rsp_rdata <= request_error ? 32'b0 : read_data;
                bus_rsp_error <= request_error;
                if (bus_req_write && !request_error) begin
                    case (bus_req_addr)
                        MSIP_ADDR:        msip <= bus_req_wdata[0];
                        MTIMECMP_LO_ADDR: mtimecmp[31:0] <= bus_req_wdata;
                        MTIMECMP_HI_ADDR: mtimecmp[63:32] <= bus_req_wdata;
                        default: ;
                    endcase
                end
            end
        end
    end
endmodule
