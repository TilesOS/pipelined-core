.option norvc
.section .text
.globl _start
_start:
    la x1, target
    lui x2, 0x00700
    addi x2, x2, 0x513  // addi x10, x0, 7
    sw x2, 0(x1)
    fence rw, rw
    fence.i
    jal x0, target
target:
    addi x10, x0, 1     // replaced before retirement
    fence.tso
    .word 0xffffffff
