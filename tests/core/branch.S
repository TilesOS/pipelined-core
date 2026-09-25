    .section .text
    .globl _start
_start:
    addi x1, x0, 1
    addi x2, x0, 2
    add  x3, x1, x2
    sub  x4, x3, x1
    beq  x4, x2, 1f
    addi x5, x0, 99       // must be flushed
1:
    jal  x6, 2f
    addi x7, x0, 88       // must be flushed
2:
    addi x8, x4, -1
    .word 0xffffffff     // deliberate trap boundary
