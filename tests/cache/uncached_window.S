.option norvc
.section .text
.globl _start
_start:
    lui t0, 0x87800
    li t1, 0x12345678
    sw t1, 0(t0)
    lbu t2, 0(t0)
    lh t3, 2(t0)
    sb t2, 15(t0)
    lbu t4, 15(t0)
    sh t3, 6(t0)
    lhu t5, 6(t0)
    lr.w.aq a0, (t0)
    addi t1, a0, 1
    sc.w.rl a1, t1, (t0)
    amoadd.w a2, t2, (t0)
    amoswap.w a3, t3, (t0)
    lw a4, 0(t0)
    fence rw, rw
    lui t0, 0x88000
    addi t0, t0, -4
    sw t1, 0(t0)
    lw a5, 0(t0)
    lui t0, 0x87800
    addi t0, t0, -4       // last word of cacheable DDR
    sw t1, 0(t0)
    lw a6, 0(t0)
    fence.i
    .word 0xffffffff
