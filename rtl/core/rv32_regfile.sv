// 32 x 32-bit integer registers: two combinational read ports for ID and one
// write port for WB. x0 is never written, so it always reads zero.
module rv32_regfile (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [4:0]  rs1,
    input  logic [4:0]  rs2,
    output logic [31:0] rs1_value,
    output logic [31:0] rs2_value,
    input  logic        write_enable,
    input  logic [4:0]  rd,
    input  logic [31:0] rd_value
);
    logic [31:0] registers [0:31];

    assign rs1_value = registers[rs1];
    assign rs2_value = registers[rs2];

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (int i = 0; i < 32; i++) registers[i] <= 0;
        end else if (write_enable && rd != 0) begin
            registers[rd] <= rd_value;
        end
    end
endmodule
