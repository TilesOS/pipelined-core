.option norvc
.option norelax
.section .text
.globl _start
_start:
    la t0, trap_handler
    csrw mtvec, t0
    li s0, 0
    li s1, 0
    # Eight locked NA4 entries. Even entries R-only; odd entries W is
    # reserved without R and must legalize to no permissions.
    li t0, 0x20001000
    csrw pmpaddr0, t0
    addi t0, t0, 1
    csrw pmpaddr1, t0
    addi t0, t0, 1
    csrw pmpaddr2, t0
    addi t0, t0, 1
    csrw pmpaddr3, t0
    addi t0, t0, 1
    csrw pmpaddr4, t0
    addi t0, t0, 1
    csrw pmpaddr5, t0
    addi t0, t0, 1
    csrw pmpaddr6, t0
    addi t0, t0, 1
    csrw pmpaddr7, t0
    li t0, 0x92919291
    csrw pmpcfg0, t0
    csrw pmpcfg1, t0
    li t0, 0x90919091
    csrr t1, pmpcfg0
    bne t0, t1, fail
    csrr t1, pmpcfg1
    bne t0, t1, fail
    li s2, 0x80004000
    li s3, 8
1:  li s1, 7
    sw zero, 0(s2) # always denied for locked entries, including M
    li s1, 5
    lw t0, 0(s2) # only odd entries fault
    addi s2, s2, 4
    addi s3, s3, -1
    bnez s3, 1b
    li t0, 12
    bne s0, t0, fail
    # Independent EX permission inputs must retain atomic access semantics:
    # LR needs R, while SC and AMOs also need W. Check precise fault causes.
    li s2, 0x80004000 # locked R-only entry
    lr.w t0, (s2)
    li s1, 7
    sc.w t1, t0, (s2)
    amoadd.w t0, zero, (s2)
    addi s2, s2, 4 # locked entry with no permissions
    li s1, 5
    lr.w t0, (s2)
    li t0, 15
    bne s0, t0, fail
    # Lock cannot be removed by cfg/address writes.
    csrw pmpcfg0, zero
    csrw pmpcfg1, zero
    csrw pmpaddr0, zero
    csrw pmpaddr7, zero
    csrr t0, pmpaddr0
    li t1, 0x20001000
    bne t0, t1, fail
    csrr t0, pmpaddr7
    li t1, 0x20001007
    bne t0, t1, fail
    # No matched PMP entry: M access succeeds; MPRV=U access fails.
    li s2, 0x80004020
    mv t0, s2
    sw zero, 0(t0)
    li s1, 5
    li t1, 0x20000
    csrw mstatus, t1
    lw t1, 0(t0)
    li t1, 0x20000
    csrc mstatus, t1
    li t0, 16
    bne s0, t0, fail
    # Trap entry/return clears an LR reservation even for an unrelated ECALL.
    li s2, 0x80004020
    lr.w t0, (s2)
    li s1, 11
    ecall
    sc.w t1, t0, (s2)
    li t0, 1
    bne t1, t0, fail
    li t0, 17
    bne s0, t0, fail
    li x31, 0x600d
2:  j 2b
trap_handler:
    csrr t3, mcause
    bne t3, s1, fail
    li t4, 11
    beq s1, t4, 4f # ECALL has no faulting data address
    csrr t3, mtval
    bne t3, s2, fail
4:
    addi s0, s0, 1
    csrr t3, mepc
    addi t3, t3, 4
    csrw mepc, t3
    mret
fail:
    li x31, 0xbad
3:  j 3b
