.option norvc
.section .text
.globl _start
_start:
    lui x1, 0x87800
    addi x2, x0, 5
    sw x2, 0(x1)
    addi x3, x0, 7
    .word 0xffffffff
