// Independent retirement history and button-triggered binary UART dump.
// Packet: "TRCE", uint16 count, then count oldest-first 17-byte records.
// Record: PC, instruction, cause, tval (little endian), {5'b0, trap, priv}.
module trace_ring_uart #(
    parameter integer UART_CLOCKS_PER_BIT = 434,
    parameter integer BUTTON_STABLE_CYCLES = 500_000
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        dump_button,
    input  logic        retire_valid,
    input  logic [31:0] retire_pc,
    input  logic [31:0] retire_insn,
    input  logic [1:0]  retire_priv,
    input  logic        retire_trap,
    input  logic [31:0] retire_cause,
    input  logic [31:0] retire_tval,
    output logic        uart_tx,
    output logic        freeze_core,
    output logic        dump_busy,
    output logic [8:0]  trace_count,
    output logic [7:0]  trace_write_ptr
);
    typedef enum logic [2:0] {IDLE, QUIESCE_ONE, QUIESCE_TWO,
                              HEADER, FETCH, RECORD} state_t;
    state_t state;
    logic [135:0] entries [0:255];
    logic [135:0] read_word;
    logic [8:0] count, snapshot_count, sent_records;
    logic [7:0] write_ptr, read_ptr;
    logic [4:0] byte_index;
    logic [2:0] header_index;
    logic button_meta, button_sync, button_stable, button_stable_prev;
    logic [$clog2(BUTTON_STABLE_CYCLES+1)-1:0] button_counter;
    logic button_rise;
    logic tx_ready, tx_valid;
    logic [7:0] tx_data;

    assign trace_count = count;
    assign trace_write_ptr = write_ptr;
    assign dump_busy = state != IDLE;
    assign freeze_core = dump_busy;
    assign button_rise = button_stable && !button_stable_prev;

    always_comb begin
        tx_valid = 0;
        tx_data = 0;
        if (state == HEADER) begin
            tx_valid = 1;
            case (header_index)
                0: tx_data = "T";
                1: tx_data = "R";
                2: tx_data = "C";
                3: tx_data = "E";
                4: tx_data = snapshot_count[7:0];
                default: tx_data = {7'b0, snapshot_count[8]};
            endcase
        end else if (state == RECORD) begin
            tx_valid = 1;
            tx_data = read_word[8*byte_index +: 8];
        end
    end

    uart_tx_byte #(.CLOCKS_PER_BIT(UART_CLOCKS_PER_BIT)) transmitter (
        .clk(clk), .rst_n(rst_n), .valid(tx_valid), .data(tx_data),
        .ready(tx_ready), .tx(uart_tx)
    );

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            button_meta <= 0;
            button_sync <= 0;
            button_stable <= 0;
            button_stable_prev <= 0;
            button_counter <= 0;
            write_ptr <= 0;
            count <= 0;
            snapshot_count <= 0;
            sent_records <= 0;
            read_ptr <= 0;
            read_word <= 0;
            byte_index <= 0;
            header_index <= 0;
            state <= IDLE;
        end else begin
            button_meta <= dump_button;
            button_sync <= button_meta;
            button_stable_prev <= button_stable;
            if (button_sync == button_stable) button_counter <= 0;
            else if (button_counter == BUTTON_STABLE_CYCLES-1) begin
                button_stable <= button_sync;
                button_counter <= 0;
            end else button_counter <= button_counter + 1'b1;

            // A completed retirement is sampled even while the core has just
            // entered the quiesce state; the snapshot occurs two clocks later.
            if (retire_valid) begin
                entries[write_ptr] <= {{5'b0, retire_trap, retire_priv},
                                       retire_tval, retire_cause,
                                       retire_insn, retire_pc};
                write_ptr <= write_ptr + 1'b1;
                if (count != 9'd256) count <= count + 1'b1;
            end
            case (state)
                IDLE: if (button_rise) state <= QUIESCE_ONE;
                QUIESCE_ONE: state <= QUIESCE_TWO;
                QUIESCE_TWO: begin
                    snapshot_count <= count;
                    read_ptr <= write_ptr - count[7:0];
                    sent_records <= 0;
                    header_index <= 0;
                    state <= HEADER;
                end
                HEADER: if (tx_valid && tx_ready) begin
                    if (header_index == 5) begin
                        state <= snapshot_count == 0 ? IDLE : FETCH;
                    end else header_index <= header_index + 1'b1;
                end
                FETCH: begin
                    read_word <= entries[read_ptr];
                    byte_index <= 0;
                    state <= RECORD;
                end
                RECORD: if (tx_valid && tx_ready) begin
                    if (byte_index == 16) begin
                        sent_records <= sent_records + 1'b1;
                        read_ptr <= read_ptr + 1'b1;
                        state <= (sent_records + 1'b1 == snapshot_count) ? IDLE : FETCH;
                    end else byte_index <= byte_index + 1'b1;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
