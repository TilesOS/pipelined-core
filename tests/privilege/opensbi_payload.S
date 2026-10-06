.option norvc
.option norelax
.section .text
.globl _start
_start:
    li sp, 0x8005f000
    mv s1, a1
    bnez a0, fail
    lw t0, 0(a1)
    li t1, 0xedfe0dd0 # DTB big-endian magic read by little-endian CPU
    bne t0, t1, fail
    la t0, supervisor_trap
    csrw stvec, t0
    li s0, 0
    # SBI v0.2 BASE get_spec_version.
    li a7, 0x10
    li a6, 0
    ecall
    bnez a0, fail
    beqz a1, fail
    # SBI TIME drives MTIP in M, then injects delegated STIP in S.
    csrr a0, time
    csrr a1, timeh
    addi a0, a0, 1000
    li a7, 0x54494d45
    li a6, 0
    ecall
    bnez a0, fail
    li t0, 0x20
    csrw sie, t0
    csrsi sstatus, 2
1:  beqz s0, 1b
    csrci sstatus, 2
    li t0, 1
    bne s0, t0, fail
    # OpenSBI's PMP firmware region denies S data reads and writes.
    li t0, 0x80000000
    lw t1, 0(t0)
    sw zero, 0(t0)
    li t0, 3
    bne s0, t0, fail
    # Resident firmware remains intact and a subsequent SBI call works.
    li a7, 0x10
    li a6, 3 # get_mvendorid
    ecall
    bnez a0, fail
    # Emit a serial marker using the standard console register path.
    la s2, message
2:  lbu s3, 0(s2)
    beqz s3, success
    li t0, 0x10000005
3:  lbu t1, 0(t0)
    andi t1, t1, 0x20
    beqz t1, 3b
    li t0, 0x10000000
    sb s3, 0(t0)
    addi s2, s2, 1
    j 2b
success:
    li x31, 0x600d
4:  j 4b
supervisor_trap:
    csrr t3, scause
    bltz t3, timer_irq
    li t4, 5
    beq t3, t4, fault_skip
    li t4, 7
    bne t3, t4, fail
fault_skip:
    csrr t3, sepc
    addi t3, t3, 4
    csrw sepc, t3
    addi s0, s0, 1
    sret
timer_irq:
    li t4, 0x80000005
    bne t3, t4, fail
    li a0, -1
    li a1, -1
    li a7, 0x54494d45
    li a6, 0
    ecall
    bnez a0, fail
    addi s0, s0, 1
    sret
fail:
    li x31, 0xbad
5:  j 5b
message: .asciz "CHECKPOINT10 SBI TIMER/PMP PASS\r\n"
