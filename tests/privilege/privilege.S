.option norvc
.option norelax
.section .text
.globl _start
_start:
    la t0, machine_vectors
    ori t0, t0, 1
    csrw mtvec, t0
    # Entry 0: 4 KiB at 0x80002000, R only (S execute and stores denied).
    li t0, 0x200009ff
    csrw pmpaddr0, t0
    # Entry 1: whole physical RV32 space RWX. Higher-priority entry wins.
    li t0, -1
    csrw pmpaddr1, t0
    li t0, 0x1f19
    csrw pmpcfg0, t0
    la t0, supervisor_vectors
    ori t0, t0, 1
    csrw stvec, t0
    li t0, 0x104 # delegate U ECALL and illegal instructions
    csrw medeleg, t0
    li t0, 0x222
    csrw mideleg, t0
    li s0, 0 # machine trap count
    li s1, 0 # supervisor trap count
    li s2, 0 # M IRQ count
    li s3, 0 # S IRQ count
    li s5, 0 # M vectored arrivals
    li s6, 0 # S vectored arrivals
    # MSIP and MTIP pending together: MSIP wins, timer follows.
    li t0, 0x02000000
    li t1, 1
    sw t1, 0(t0)
    li t0, 0x02004000
    sw zero, 0(t0)
    sw zero, 4(t0)
    li t0, 0x88
    csrw mie, t0
    csrsi mstatus, 8
    li t0, 2
1:  bne s2, t0, 1b
    csrci mstatus, 8
    csrw mie, zero
    # PMP locked TOR bounds: locked entry 3 also locks pmpaddr2.
    li t0, 0x30000000
    csrw pmpaddr2, t0
    li t0, 0x30000001
    csrw pmpaddr3, t0
    li t0, 0x89001f19
    csrw pmpcfg0, t0
    csrw pmpaddr2, zero
    csrr t1, pmpaddr2
    li t0, 0x30000000
    bne t0, t1, fail
    # Lower unlocked full-space entry deliberately shadows this locked region.
    # Entry 7 locks a NAPOT region and must resist cfg/address writes.
    li t0, 0x30001000
    csrw pmpaddr7, t0
    li t0, 0x99000000
    csrw pmpcfg1, t0
    csrw pmpaddr7, zero
    csrr t1, pmpaddr7
    li t0, 0x30001000
    bne t0, t1, fail
    csrw pmpcfg1, zero
    csrr t1, pmpcfg1
    li t0, 0x99000000
    bne t0, t1, fail
    # M-mode bypasses unlocked PMP; MPRV applies S permissions to data.
    li t0, 0x80002000
    lw t1, 0(t0)
    li t1, 0x20800 # MPRV=1, MPP=S
    csrw mstatus, t1
    sw zero, 0(t0)
    li t1, 0x20000
    csrc mstatus, t1
    la t0, supervisor
    csrw mepc, t0
    li t0, 0x800
    csrw mstatus, t0
    mret
supervisor:
    # S ECALL is not delegated; M handler preserves S mode through MRET.
    ecall
    # Illegal M CSR in S delegated to S, then SRET.
    csrr t0, mscratch
    # Read-only PMP region allows a load; rejects store without memory effects.
    li t0, 0x80002000
    lw t1, 0(t0)
    li t2, 0x12345678
    bne t1, t2, fail
    sw zero, 0(t0)
    # Execute denied: branch target fetch fault, M handler skips via saved resume.
    la s4, after_execute_fault
    jalr zero, t0, 0
after_execute_fault:
    # Delegated S external IRQ from UART THRE via PLIC.
    li t0, 0x0c000004
    li t1, 1
    sw t1, 0(t0)
    li t0, 0x0c002080
    li t1, 2
    sw t1, 0(t0)
    li t0, 0x10000001
    sb t1, 0(t0)
    li t0, 0x200
    csrw sie, t0
    csrsi sstatus, 2
2:  beqz s3, 2b
    csrci sstatus, 2
    csrw sie, zero
    # U-mode transition and U ECALL delegation.
    la t0, user
    csrw sepc, t0
    li t0, 0x100
    csrc sstatus, t0
    sret
user:
    ecall
    # Illegal S CSR in U delegated to S.
    csrr t0, sscratch
    li t0, 3
    bne s1, t0, fail
    li t0, 4
    bne s0, t0, fail
    li t0, 2
    bne s2, t0, fail
    li t0, 1
    bne s3, t0, fail
    li t0, 2
    bne s5, t0, fail
    li t0, 1
    bne s6, t0, fail
    li t0, 0x80002000
    lw t1, 0(t0)
    li t2, 0x12345678
    bne t1, t2, fail
    li x31, 0x600d
3:  j 3b
.balign 64
machine_vectors:
    j machine_trap
    j fail
    j fail
    j machine_vector_irq
    j fail
    j fail
    j fail
    j machine_vector_irq
    j fail
    j fail
    j fail
    j machine_vector_irq
machine_vector_irq:
    addi s5, s5, 1
    j machine_trap
.balign 64
supervisor_vectors:
    j supervisor_trap
    j fail
    j fail
    j fail
    j fail
    j fail
    j fail
    j fail
    j fail
    j supervisor_vector_irq
supervisor_vector_irq:
    addi s6, s6, 1
    j supervisor_trap
machine_trap:
    csrr t3, mcause
    bltz t3, machine_irq
    addi s0, s0, 1
    li t4, 1
    beq t3, t4, execute_fault
    li t4, 7
    beq t3, t4, machine_skip
    li t4, 9
    bne t3, t4, fail
machine_skip:
    csrr t3, mepc
    addi t3, t3, 4
    csrw mepc, t3
    mret
execute_fault:
    csrw mepc, s4
    mret
machine_irq:
    li t4, 0x80000003
    beq t3, t4, software_irq
    li t4, 0x80000007
    bne t3, t4, fail
    li t4, 1
    bne s2, t4, fail
    li t3, 0x02004000
    li t4, -1
    sw t4, 4(t3)
    sw t4, 0(t3)
    addi s2, s2, 1
    mret
software_irq:
    bnez s2, fail
    li t3, 0x02000000
    sw zero, 0(t3)
    addi s2, s2, 1
    mret
supervisor_trap:
    csrr t3, scause
    bltz t3, supervisor_irq
    addi s1, s1, 1
    li t4, 2
    beq t3, t4, supervisor_skip
    li t4, 8
    bne t3, t4, fail
supervisor_skip:
    csrr t3, sepc
    addi t3, t3, 4
    csrw sepc, t3
    sret
supervisor_irq:
    li t4, 0x80000009
    bne t3, t4, fail
    li t3, 0x0c201004
    lw t4, 0(t3)
    li t5, 1
    bne t4, t5, fail
    li t5, 0x10000002
    lbu t6, 0(t5)
    li t5, 2
    bne t6, t5, fail
    sw t4, 0(t3)
    addi s3, s3, 1
    sret
fail:
    li x31, 0xbad
4:  j 4b
.section .data
.globl protected_word
protected_word: .word 0x12345678
