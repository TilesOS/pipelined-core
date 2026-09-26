.option norvc
.section .text
.globl _start
_start:
    lui x1, 0x80001
    addi x2, x0, 5
    sw x2, 0(x1)
    lr.w x3, (x1)
    addi x4, x3, 7
    sc.w x5, x4, (x1)
    lw x6, 0(x1)
    sc.w x7, x2, (x1)
    lw x8, 0(x1)
    lr.w x23, (x1)
    sw x2, 4(x1)
    sc.w x24, x4, (x1) // different word preserves reservation
    amoadd.w x9, x2, (x1)
    amoswap.w x10, x4, (x1)
    amoxor.w x11, x2, (x1)
    amoor.w x12, x2, (x1)
    amoand.w x13, x4, (x1)
    amomin.w x14, x3, (x1)
    amomax.w x15, x4, (x1)
    amominu.w x16, x3, (x1)
    amomaxu.w x17, x4, (x1)
    lr.w.aq x18, (x1)
    sc.w.rl x19, x2, (x1)
    lw x20, 0(x1)
    .word 0xffffffff
