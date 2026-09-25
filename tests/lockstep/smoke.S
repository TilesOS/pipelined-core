/* Checkpoint 3 reference program. The trace fixture represents six insns and a trap. */
    .section .text
    .globl _start
_start:
    addi x1, x0, 5
    addi x2, x1, 7
    lui  x3, 0x80001
    sw   x2, 0(x3)
    lw   x4, 0(x3)
    addi x5, x4, 1
    .word 0xffffffff  /* deliberate illegal-instruction exception */

    .section .bss
smoke_data:
    .word 0
