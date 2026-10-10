.option norvc
.section .text
.globl _start
_start:
    lui x1, 0x80004
    addi x2, x0, 5
    sw x2, 0(x1)
    fence.i
    addi x3, x0, 7
    .word 0xffffffff
