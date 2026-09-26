.option norvc
.section .text
.globl _start
_start:
    addi x1, x0, 0x55
    csrrw x2, mscratch, x1
    csrrs x3, mscratch, x0
    csrrsi x4, mscratch, 2
    csrrci x5, mscratch, 1
    csrrwi x6, mscratch, 7
    csrrw x0, mscratch, x1
    csrrs x7, mscratch, x0
    csrr x8, misa
    csrr x9, mhartid
    csrr x10, mvendorid
    addi x11, x0, 8
    csrrw x12, mstatus, x11
    csrrs x13, mstatus, x0
    csrrc x14, mstatus, x11
    csrrs x15, mstatus, x0
    csrrw x16, mie, x11
    csrrs x17, mie, x0
    lui x18, 0x80000
    csrrw x19, mtvec, x18
    csrrs x20, mtvec, x0
    addi x18, x18, 1
    csrrw x19, mtvec, x18
    csrrs x20, mtvec, x0
    addi x18, x18, 1
    csrrw x21, mepc, x18
    csrrs x22, mepc, x0
    .word 0xffffffff
