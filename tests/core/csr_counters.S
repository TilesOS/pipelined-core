.option norvc
.section .text
.globl _start
_start:
    addi x1, x0, 20
    csrw minstret, x1
    csrr x2, minstret
    csrr x3, minstreth
    csrr x4, mcycle
    csrr x5, mcycle
    addi x6, x0, 100
    csrw mcycle, x6
    csrr x7, mcycle
    addi x8, x0, 1
    csrw mcycleh, x8
    csrr x9, mcycleh
    csrw minstreth, x8
    csrr x10, minstreth
    .word 0xffffffff
