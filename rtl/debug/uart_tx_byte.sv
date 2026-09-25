// Standalone 8N1 transmitter for the early debug path. The system UART at
// checkpoint 10 will share the physical TX pin through a defined arbiter.
module uart_tx_byte #(
    parameter integer CLOCKS_PER_BIT = 434
) (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       valid,
    input  logic [7:0] data,
    output logic       ready,
    output logic       tx
);
    logic [9:0] frame;
    logic [3:0] bit_index;
    logic [$clog2(CLOCKS_PER_BIT+1)-1:0] tick;
    logic busy;
    assign ready = !busy;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            frame <= 10'h3ff;
            bit_index <= 0;
            tick <= 0;
            busy <= 0;
            tx <= 1;
        end else if (!busy) begin
            tx <= 1;
            if (valid) begin
                frame <= {1'b1, data, 1'b0};
                bit_index <= 0;
                tick <= 0;
                busy <= 1;
                tx <= 0;
            end
        end else if (tick == CLOCKS_PER_BIT-1) begin
            tick <= 0;
            if (bit_index == 9) begin
                busy <= 0;
                tx <= 1;
            end else begin
                bit_index <= bit_index + 1'b1;
                tx <= frame[bit_index + 1'b1];
            end
        end else tick <= tick + 1'b1;
    end
endmodule
