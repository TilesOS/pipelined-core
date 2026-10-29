// Iterative radix-2 DIV/DIVU/REM/REMU: 32 cycles, or one for divide by zero
// and signed overflow. EX holds the instruction until ready.
module rv32_divider (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        advance,  // pipeline not halted or waiting on WB
    input  logic        cancel,   // EX redirect or EX/MEM fault
    input  logic        kill,     // trap entry or xRET in WB
    input  logic        start,    // a DIV/REM is in EX
    input  logic        is_signed,
    input  logic [31:0] dividend,
    input  logic [31:0] divisor,
    output logic        ready,
    output logic [31:0] quotient,
    output logic [31:0] remainder
);
    logic active, special, negate_quotient, negate_remainder;
    logic [5:0] count;
    logic [31:0] shift_dividend, abs_divisor, partial_quotient, partial_remainder;
    logic [31:0] special_quotient, special_remainder;
    logic [32:0] trial;

    assign ready = active && count == 0;
    assign trial = {partial_remainder, shift_dividend[31]};
    assign quotient = special ? special_quotient :
        (negate_quotient ? -partial_quotient : partial_quotient);
    assign remainder = special ? special_remainder :
        (negate_remainder ? -partial_remainder : partial_remainder);

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            active <= 0;
            count <= 0;
            shift_dividend <= 0;
            abs_divisor <= 0;
            partial_quotient <= 0;
            partial_remainder <= 0;
            negate_quotient <= 0;
            negate_remainder <= 0;
            special <= 0;
            special_quotient <= 0;
            special_remainder <= 0;
        end else if (advance) begin
            if (cancel || ready) begin
                active <= 0;
            end else if (start && !active) begin
                active <= 1;
                special <= divisor == 0 ||
                    (is_signed && dividend == 32'h8000_0000 && divisor == 32'hffff_ffff);
                count <= (divisor == 0 ||
                    (is_signed && dividend == 32'h8000_0000 && divisor == 32'hffff_ffff)) ? 6'd0 : 6'd32;
                special_quotient <= divisor == 0 ? 32'hffff_ffff : 32'h8000_0000;
                special_remainder <= divisor == 0 ? dividend : 32'b0;
                negate_quotient <= is_signed && (dividend[31] ^ divisor[31]);
                negate_remainder <= is_signed && dividend[31];
                shift_dividend <= (is_signed && dividend[31]) ? -dividend : dividend;
                abs_divisor <= (is_signed && divisor[31]) ? -divisor : divisor;
                partial_quotient <= 0;
                partial_remainder <= 0;
            end else if (active && count != 0) begin
                count <= count - 6'd1;
                shift_dividend <= {shift_dividend[30:0], 1'b0};
                if (trial >= {1'b0, abs_divisor}) begin
                    partial_remainder <= trial[31:0] - abs_divisor;
                    partial_quotient <= {partial_quotient[30:0], 1'b1};
                end else begin
                    partial_remainder <= trial[31:0];
                    partial_quotient <= {partial_quotient[30:0], 1'b0};
                end
            end
            if (kill) active <= 0;
        end
    end
endmodule
