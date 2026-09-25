    .section .text
    .globl _start
_start:
    addi x1, x1, 1
    addi x2, x2, 3
    jal  x0, _start
