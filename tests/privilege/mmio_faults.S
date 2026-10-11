.option norvc
.option norelax
.section .text
.globl _start
_start:
    la t0, trap_handler
    csrw mtvec, t0
    li s0, 0
    li s1, 5
    li s2, 0x10010000
    li t1, 0x55
fault_load:
    lw t1, 0(s2)
    li t0, 0x55
    bne t1, t0, fail # failed load never writes rd
    li s1, 7
    li s2, 0x10000007
    li t0, 0xaa
fault_store:
    # Aligned word access to UART is rejected by the device, not by decode.
    li s2, 0x10000004
    sw t0, 0(s2)
    li t0, 0x10000004
    lbu t1, 0(t0)
    bnez t1, fail
    li t0, 0x10000007
    lbu t1, 0(t0)
    bnez t1, fail
    li s1, 5
    li s2, 0x02000000
    lbu t1, 0(s2) # CLINT only accepts words
    li t0, 3
    bne s0, t0, fail
    li x31, 0x600d
1:  j 1b
trap_handler:
    csrr t3, mcause
    bne t3, s1, fail
    csrr t3, mtval
    bne t3, s2, fail
    addi s0, s0, 1
    csrr t3, mepc
    addi t3, t3, 4
    csrw mepc, t3
    mret
fail:
    li x31, 0xbad
2:  j 2b
