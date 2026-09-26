.option norvc
.section .text
.globl _start
_start:
    lui x1, 0x80001
    addi x2, x0, 5
    sw x2, 0(x1)
    amoadd.w x3, x2, (x1)
    lw x4, 0(x1)
    .word 0xffffffff
