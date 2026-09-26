.option norvc
.section .text
.globl _start
_start:
    addi x1, x0, -7
    addi x2, x0, 3
    addi x3, x0, 0
    lui x4, 0x80000
    addi x5, x0, -1
    mul x6, x1, x2
    mulh x7, x1, x2
    mulhsu x8, x1, x2
    mulhu x9, x1, x2
    div x10, x1, x2
    divu x11, x1, x2
    rem x12, x1, x2
    remu x13, x1, x2
    div x14, x1, x3
    divu x15, x1, x3
    rem x16, x1, x3
    remu x17, x1, x3
    div x18, x4, x5
    rem x19, x4, x5
    mul x20, x4, x5
    mulh x21, x4, x5
    .word 0xffffffff
