.option norvc
.section .text
.globl _start
_start:
    jal ra, target
    la t0, target
    li t1, 0x00700513       // addi a0, zero, 7
    sw t1, 0(t0)
    lui t2, 0x80005
    li t3, 0x12345678
    sw t3, 28(t2)          // dirty an unrelated set and second beat
    fence rw, rw
    fence.i
    jal ra, target         // must refetch the previously executed line
    li t1, 0x00b00513       // addi a0, zero, 11
    sw t1, 0(t0)
    fence.i
    jal ra, target
    .word 0xffffffff
.org 0x201c
target:
    addi a0, zero, 1
    ret
