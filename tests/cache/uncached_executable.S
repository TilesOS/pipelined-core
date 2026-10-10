.option norvc
.section .text
.globl _start
_start:
    lui t0, 0x87800
    li t1, 0x00a00513     // addi a0, zero, 10
    sw t1, 0(t0)
    li t1, 0x00008067     // ret
    sw t1, 4(t0)
    fence.i
    jalr ra, 0(t0)
    li t1, 0x01400513     // addi a0, zero, 20
    sw t1, 0(t0)
    fence.i
    jalr ra, 0(t0)
    .word 0xffffffff
