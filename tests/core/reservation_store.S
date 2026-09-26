.option norvc
.section .text
.globl _start
_start:
    lui x1, 0x80001
    addi x2, x0, 5
    sw x2, 0(x1)
    lr.w x3, (x1)
    sw x2, 0(x1)
    sc.w x5, x2, (x1)
    lw x6, 0(x1)
    .word 0xffffffff
