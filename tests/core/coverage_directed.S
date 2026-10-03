// Close specific gaps reported by the fixed CPU functional coverage model.
.option norvc
.section .text
.globl _start
_start:
    addi x1, x0, -1
    addi x2, x0, 1
    // All four branches must fall through. A wrong redirect reaches EBREAK.
    blt x2, x1, fail
    bge x1, x2, fail
    bltu x1, x2, fail
    bgeu x2, x1, fail
    csrw mcause, x2
    csrr x3, mcause
    csrw mtval, x1
    csrr x4, mtval
    lui x5, 0x80001
    sw x2, 0(x5)
    lr.w.aqrl x6, (x5)
    sc.w.aqrl x7, x1, (x5)
    amoadd.w.aqrl x8, x2, (x5)
    lw x9, 0(x5)
    .word 0xffffffff
fail:
    ebreak
