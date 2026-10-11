timeunit 1ns;
timeprecision 1ps;
// ns16550a, byte-spaced registers, 16-byte FIFOs and programmable framing.
// Divisor 27 is the nearest integer to 50 MHz / (16 * 115200).
module uart16550 #(
    parameter logic [15:0] DEFAULT_DIVISOR = 16'd27
) (
    input logic clk, rst_n, uart_rx,
    output logic uart_tx, uart_tx_idle, irq,
    input logic bus_req_valid, bus_req_write,
    output logic bus_req_ready,
    input logic [31:0] bus_req_addr, bus_req_wdata,
    input logic [1:0] bus_req_size,
    input logic [3:0] bus_req_wstrb,
    output logic bus_rsp_valid, bus_rsp_error,
    input logic bus_rsp_ready,
    output logic [31:0] bus_rsp_rdata
);
    logic [7:0] ier, lcr, mcr, scr, fcr, msr_delta;
    logic [15:0] divisor;
    logic [7:0] tx_fifo [16], rx_fifo [16];
    logic [2:0] rx_errors [16]; // parity, framing, break (LSR[4:2])
    logic [3:0] tx_head, tx_tail, rx_head, rx_tail;
    logic [4:0] tx_count, rx_count;
    logic overrun, thre_pending;
    logic [7:0] lsr, iir, msr, read_data;
    logic request_error, accept, rd, wr, tx_push, tx_pop, rx_push, rx_pop;
    logic clear_rx, clear_tx, clear_lsr, clear_thre;
    logic [4:0] depth, trigger_level;
    logic [19:0] bit_cycles;
    logic [25:0] timeout_count, timeout_cycles;
    logic [4:0] character_half_bits;
    logic timeout_irq, fifo_error;
    logic [11:0] tx_frame;
    logic [3:0] tx_bits;
    logic [19:0] tx_timer;
    logic tx_busy;
    (* async_reg = "true" *) logic rx_meta, rx_sync;
    logic serial_rx, serial_tx;
    typedef enum logic [2:0] {RX_IDLE, RX_START, RX_DATA, RX_PARITY, RX_STOP, RX_WAIT} rxstate_t;
    rxstate_t rx_state;
    logic [19:0] rx_timer;
    logic [7:0] rx_shift;
    logic [3:0] rx_bit;
    logic [2:0] rx_error;
    logic rx_parity;
    logic [3:0] data_bits;
    logic [7:0] data_mask;
    logic [3:0] modem_level, modem_previous;

    assign bit_cycles = {divisor == 0 ? 16'd1 : divisor, 4'b0};
    assign data_bits = 4'd5 + {2'b0, lcr[1:0]};
    assign data_mask = 8'hff >> (4'd8 - data_bits);
    assign depth = fcr[0] ? 5'd16 : 5'd1;
    assign trigger_level = !fcr[0] ? 5'd1 : fcr[7:6] == 0 ? 5'd1 :
                           fcr[7:6] == 1 ? 5'd4 : fcr[7:6] == 2 ? 5'd8 : 5'd14;
    assign serial_tx = lcr[6] ? 1'b0 : tx_busy ? tx_frame[0] : 1'b1;
    assign uart_tx = mcr[4] ? 1'b1 : serial_tx; // isolate external TX in loopback
    assign uart_tx_idle = !tx_busy && tx_count == 0 && !lcr[6];
    assign serial_rx = mcr[4] ? serial_tx : rx_sync;
    // External modem pins are absent: CTS/DSR/DCD are asserted, RI is low.
    assign modem_level = mcr[4] ? {mcr[3], mcr[2], mcr[0], mcr[1]} : 4'b1011;
    assign msr = {modem_level, msr_delta[3:0]};
    assign character_half_bits = 5'd2 * (5'd1 + {1'b0, data_bits} + {4'b0, lcr[3]} +
        (lcr[2] ? 5'd2 : 5'd1)) - {4'b0, lcr[2] && data_bits == 5};
    assign timeout_cycles = 26'(bit_cycles) * 26'(character_half_bits) * 26'd2;
    assign timeout_irq = fcr[0] && rx_count != 0 && timeout_count >= timeout_cycles;
    always_comb begin
        fifo_error = 0;
        for (int i = 0; i < 16; i++)
            if (i < int'(rx_count) && rx_errors[4'(rx_head + 4'(i))] != 0) fifo_error = 1;
        lsr = {fcr[0] && fifo_error, !tx_busy && tx_count == 0, tx_count == 0,
               rx_count != 0 ? rx_errors[rx_head] : 3'b0, overrun, rx_count != 0};
        iir = fcr[0] ? 8'hc1 : 8'h01;
        if (ier[2] && |lsr[4:1]) iir[3:0] = 4'h6;
        else if (ier[0] && rx_count >= trigger_level) iir[3:0] = 4'h4;
        else if (ier[0] && timeout_irq) iir[3:0] = 4'hc;
        else if (ier[1] && thre_pending) iir[3:0] = 4'h2;
        else if (ier[3] && |msr_delta[3:0]) iir[3:0] = 4'h0;
        read_data = 0;
        case (bus_req_addr[2:0])
            0: read_data = lcr[7] ? divisor[7:0] : rx_count != 0 ? rx_fifo[rx_head] : 8'b0;
            1: read_data = lcr[7] ? divisor[15:8] : ier;
            2: read_data = iir;
            3: read_data = lcr;
            4: read_data = mcr;
            5: read_data = lsr;
            6: read_data = msr;
            7: read_data = scr;
            default: ;
        endcase
    end
    assign irq = !iir[0];
    assign bus_req_ready = !bus_rsp_valid;
    assign request_error = bus_req_addr[31:3] != 29'(32'h1000_0000 >> 3) ||
        bus_req_size != 0 || (bus_req_write && bus_req_wstrb != 4'h1);
    assign accept = bus_req_valid && bus_req_ready;
    assign rd = accept && !request_error && !bus_req_write;
    assign wr = accept && !request_error && bus_req_write;
    assign clear_rx = wr && bus_req_addr[2:0] == 2 &&
        (bus_req_wdata[1] || bus_req_wdata[0] != fcr[0]);
    assign clear_tx = wr && bus_req_addr[2:0] == 2 &&
        (bus_req_wdata[2] || bus_req_wdata[0] != fcr[0]);
    assign tx_push = wr && bus_req_addr[2:0] == 0 && !lcr[7] && tx_count < depth;
    assign tx_pop = !tx_busy && tx_count != 0 && !clear_tx;
    assign rx_push = rx_state == RX_STOP && rx_timer == 0;
    assign rx_pop = rd && bus_req_addr[2:0] == 0 && !lcr[7] && rx_count != 0;
    assign clear_lsr = rd && bus_req_addr[2:0] == 5;
    assign clear_thre = rd && bus_req_addr[2:0] == 2 && iir[3:0] == 2;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_meta <= 1; rx_sync <= 1;
        end else begin rx_meta <= uart_rx; rx_sync <= rx_meta; end
    end
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ier <= 0; lcr <= 8'h03; mcr <= 0; scr <= 0; fcr <= 0;
            divisor <= DEFAULT_DIVISOR;
            tx_head <= 0; tx_tail <= 0; tx_count <= 0;
            rx_head <= 0; rx_tail <= 0; rx_count <= 0;
            overrun <= 0; thre_pending <= 1; timeout_count <= 0;
            bus_rsp_valid <= 0; bus_rsp_error <= 0; bus_rsp_rdata <= 0;
            tx_busy <= 0; tx_timer <= 0; tx_frame <= '1; tx_bits <= 0;
            rx_state <= RX_IDLE; rx_timer <= 0; rx_shift <= 0; rx_bit <= 0;
            rx_error <= 0; rx_parity <= 0;
            modem_previous <= 4'b1011; msr_delta <= 0;
            for (int i = 0; i < 16; i++) rx_errors[i] <= 0;
        end else begin
            if (bus_rsp_valid && bus_rsp_ready) bus_rsp_valid <= 0;
            if (accept) begin
                bus_rsp_valid <= 1;
                bus_rsp_error <= request_error;
                bus_rsp_rdata <= request_error ? 0 : {24'b0, read_data};
            end
            modem_previous <= modem_level;
            if (rd && bus_req_addr[2:0] == 6) msr_delta <= 0;
            // Delta RI is set only on a trailing edge; other pins on either edge.
            if (modem_level != modem_previous)
                msr_delta <= msr_delta | {4'b0, modem_level[3] ^ modem_previous[3],
                    modem_previous[2] && !modem_level[2],
                    modem_level[1:0] ^ modem_previous[1:0]};
            if (wr) begin
                case (bus_req_addr[2:0])
                    0: if (lcr[7]) divisor[7:0] <= bus_req_wdata[7:0];
                    1: if (lcr[7]) divisor[15:8] <= bus_req_wdata[7:0];
                       else begin
                           ier <= {4'b0, bus_req_wdata[3:0]};
                           if (bus_req_wdata[1] && !ier[1] && tx_count == 0) thre_pending <= 1;
                       end
                    2: fcr <= bus_req_wdata[7:0] & 8'hc9;
                    3: lcr <= bus_req_wdata[7:0];
                    4: mcr <= bus_req_wdata[7:0] & 8'h1f;
                    7: scr <= bus_req_wdata[7:0];
                    default: ;
                endcase
            end
            if (clear_thre || tx_push) thre_pending <= 0;
            if (tx_pop && tx_count == 1 && !tx_push) thre_pending <= 1;
            if (clear_tx) begin
                tx_count <= 0; tx_head <= 0; tx_tail <= 0; thre_pending <= 1;
            end else begin
                case ({tx_push, tx_pop})
                    2'b10: tx_count <= tx_count + 1'b1;
                    2'b01: tx_count <= tx_count - 1'b1;
                    default: ;
                endcase
                if (tx_push) begin tx_fifo[tx_tail] <= bus_req_wdata[7:0]; tx_tail <= tx_tail + 1'b1; end
                if (tx_pop) tx_head <= tx_head + 1'b1;
            end
            if (tx_pop) begin
                tx_frame <= 12'hfff;
                tx_frame[0] <= 0;
                for (int i = 0; i < 8; i++)
                    if (i < int'(data_bits)) tx_frame[i+1] <= tx_fifo[tx_head][i];
                if (lcr[3]) tx_frame[data_bits+1] <= lcr[5] ? !lcr[4] :
                    (^(tx_fifo[tx_head] & data_mask)) ^ !lcr[4];
                tx_bits <= 4'd1 + data_bits + {3'b0, lcr[3]} + (lcr[2] ? 4'd2 : 4'd1);
                tx_timer <= bit_cycles - 1'b1; tx_busy <= 1;
            end else if (tx_busy) begin
                if (tx_timer != 0) tx_timer <= tx_timer - 1'b1;
                else if (tx_bits == 1) tx_busy <= 0;
                else begin
                    tx_frame <= {1'b1, tx_frame[11:1]};
                    tx_bits <= tx_bits - 1'b1;
                    // 16550 uses 1.5 stop bits for five-bit words with STB set.
                    tx_timer <= lcr[2] && data_bits == 5 && tx_bits == 2 ?
                        (bit_cycles >> 1) - 1'b1 : bit_cycles - 1'b1;
                end
            end
            if (clear_lsr) begin
                overrun <= 0;
                if (rx_count != 0) rx_errors[rx_head] <= 0;
            end
            if (clear_rx) begin
                rx_count <= 0; rx_head <= 0; rx_tail <= 0; overrun <= 0;
                for (int i = 0; i < 16; i++) rx_errors[i] <= 0;
            end else begin
                case ({rx_push && (rx_count < depth || rx_pop), rx_pop})
                    2'b10: rx_count <= rx_count + 1'b1;
                    2'b01: rx_count <= rx_count - 1'b1;
                    default: ;
                endcase
                if (rx_pop) rx_head <= rx_head + 1'b1;
                if (rx_push) begin
                    if (rx_count < depth || rx_pop) begin
                        rx_fifo[rx_tail] <= rx_shift;
                        rx_errors[rx_tail] <= {(!serial_rx && rx_shift == 0),
                            !serial_rx, rx_error[0]};
                        rx_tail <= rx_tail + 1'b1;
                    end else overrun <= 1;
                end
            end
            if (rx_push || rx_pop || clear_rx || rx_count == 0) timeout_count <= 0;
            else if (!timeout_irq) timeout_count <= timeout_count + 1'b1;
            if (rx_timer != 0) rx_timer <= rx_timer - 1'b1;
            case (rx_state)
                RX_IDLE: if (!serial_rx) begin
                    rx_state <= RX_START; rx_timer <= (bit_cycles >> 1) - 1'b1;
                    rx_shift <= 0; rx_bit <= 0; rx_error <= 0; rx_parity <= 0;
                end
                RX_START: if (rx_timer == 0) begin
                    if (serial_rx) rx_state <= RX_IDLE;
                    else begin rx_state <= RX_DATA; rx_timer <= bit_cycles - 1'b1; end
                end
                RX_DATA: if (rx_timer == 0) begin
                    rx_shift[rx_bit[2:0]] <= serial_rx;
                    rx_parity <= rx_parity ^ serial_rx;
                    rx_bit <= rx_bit + 1'b1; rx_timer <= bit_cycles - 1'b1;
                    if (rx_bit == data_bits - 1'b1) rx_state <= lcr[3] ? RX_PARITY : RX_STOP;
                end
                RX_PARITY: if (rx_timer == 0) begin
                    rx_error[0] <= serial_rx != (lcr[5] ? !lcr[4] : rx_parity ^ !lcr[4]);
                    rx_state <= RX_STOP; rx_timer <= bit_cycles - 1'b1;
                end
                RX_STOP: if (rx_timer == 0) rx_state <= serial_rx ? RX_IDLE : RX_WAIT;
                RX_WAIT: if (serial_rx) rx_state <= RX_IDLE;
                default: rx_state <= RX_IDLE;
            endcase
        end
    end
endmodule
