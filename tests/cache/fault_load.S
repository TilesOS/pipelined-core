.option norvc
.section .text
.globl _start
_start:
    lui x1, 0x80004
    lw x2, 0(x1)
    sw x3, 4(x1)
    .word 0xffffffff
