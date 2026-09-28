// 100 MHz Nexys A7 oscillator to the contracted 50 MHz core/fabric clock.
// MIG owns its independent user clock and DDR2 timing constraints.
module checkpoint8_core_clock (
    input  logic clk100,
    input  logic rst_n,
    output logic clk50,
    output logic clk200,
    output logic locked
);
    wire feedback;
    wire clk50_unbuffered;
    wire clk200_unbuffered;
    PLLE2_BASE #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKFBOUT_MULT(10),
        .CLKFBOUT_PHASE(0.0),
        .CLKIN1_PERIOD(10.0),
        .CLKOUT0_DIVIDE(20),
        .CLKOUT0_DUTY_CYCLE(0.5),
        .CLKOUT0_PHASE(0.0),
        .CLKOUT1_DIVIDE(5),
        .CLKOUT1_DUTY_CYCLE(0.5),
        .CLKOUT1_PHASE(0.0),
        .DIVCLK_DIVIDE(1),
        .REF_JITTER1(0.010)
    ) pll (
        .CLKIN1(clk100), .CLKFBIN(feedback), .CLKFBOUT(feedback),
        .CLKOUT0(clk50_unbuffered), .CLKOUT1(clk200_unbuffered), .CLKOUT2(),
        .CLKOUT3(), .CLKOUT4(), .CLKOUT5(),
        .LOCKED(locked), .PWRDWN(1'b0), .RST(!rst_n)
    );
    BUFG core_clock_buffer (.I(clk50_unbuffered), .O(clk50));
    BUFG ref_clock_buffer (.I(clk200_unbuffered), .O(clk200));
endmodule
