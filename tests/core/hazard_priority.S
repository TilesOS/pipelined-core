// Older MEM access fault coincides with younger EX illegal-instruction detection.
// Only the load fault may retire or contribute hazard/trap cross samples.
.option norvc
.section .text
.globl _start
_start:
    lui x1, 0x80010
    addi x2, x0, 9
    lw x3, 0(x1)
    .word 0xffffffff
    sw x2, 4(x1)
