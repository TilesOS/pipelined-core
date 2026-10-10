.option norvc
.option norelax
.section .text
.globl _start
_start:
    li s0, 0x10030000
    li s1, 1
    sw s1, 0(s0)
    li s2, 0x80010000
    li t0, 0x12345678
    sw t0, 0(s2)
    lbu t1, 0(s2)
    li t2, 0x78
    bne t1, t2, fail
    lhu t1, 0(s2)
    li t2, 0x5678
    bne t1, t2, fail
    li t0, 0x9a
    sb t0, 1(s2)
    li t0, 0xbcde
    sh t0, 2(s2)
    lw t1, 0(s2)
    li t2, 0xbcde9a78
    bne t1, t2, fail

    li s1, 2
    sw s1, 0(s0)
    li s3, 0x80011000
    li s4, 0x80012000
    li t0, 0x11223344
    sw t0, 0(s3)
    li t0, 0x55667788
    sw t0, 0(s4)
    lw t1, 0(s2)
    li t2, 0xbcde9a78
    bne t1, t2, fail
    lw t1, 0(s3)
    li t2, 0x11223344
    bne t1, t2, fail
    lw t1, 0(s4)
    li t2, 0x55667788
    bne t1, t2, fail

    # Write all eight words in each of 512 lines, then reload after a clean.
    li s1, 3
    sw s1, 0(s0)
    li s2, 0x80020000
    li s3, 4096
    li s4, 0xa5a55a5a
1:  xor t0, s2, s4
    sw t0, 0(s2)
    addi s2, s2, 4
    addi s3, s3, -1
    bnez s3, 1b
    fence.i
    li s2, 0x80020000
    li s3, 4096
2:  lw t1, 0(s2)
    xor t2, s2, s4
    bne t1, t2, fail
    addi s2, s2, 4
    addi s3, s3, -1
    bnez s3, 2b

    # Previously executed cached code must see both FENCE.I rewrites.
    li s1, 4
    sw s1, 0(s0)
    li s2, 0x80008000
    li t0, 0x01100513
    sw t0, 0(s2)
    li t0, 0x00008067
    sw t0, 4(s2)
    fence.i
    jalr ra, 0(s2)
    li t2, 17
    bne a0, t2, fail
    li t0, 0x02a00513
    sw t0, 0(s2)
    fence.i
    jalr ra, 0(s2)
    li t2, 42
    bne a0, t2, fail
    # Three executable lines sharing one I-cache set force an eviction.
    li s3, 0x80009000
    li s4, 0x8000a000
    li t0, 0x01600513
    sw t0, 0(s3)
    li t0, 0x01700513
    sw t0, 0(s4)
    li t0, 0x00008067
    sw t0, 4(s3)
    sw t0, 4(s4)
    fence.i
    jalr ra, 0(s3)
    li t2, 22
    bne a0, t2, fail
    jalr ra, 0(s4)
    li t2, 23
    bne a0, t2, fail
    jalr ra, 0(s2)
    li t2, 42
    bne a0, t2, fail

    li s1, 5
    sw s1, 0(s0)
    li s2, 0x877ffffc
    li t0, 0xcafebabe
    sw t0, 0(s2)
    lw t1, 0(s2)
    bne t0, t1, fail
    li s2, 0x87800000
    li t0, 0xdeadbeef
    sw t0, 0(s2)
    lw t1, 0(s2)
    bne t0, t1, fail
    li s2, 0x87fffffc
    sw t0, 0(s2)
    lw t1, 0(s2)
    bne t0, t1, fail
    # The uncached executable pool sees rewrites with plain FENCE.
    li s2, 0x87801000
    li t0, 0x00300513
    sw t0, 0(s2)
    li t0, 0x00008067
    sw t0, 4(s2)
    fence
    jalr ra, 0(s2)
    li t2, 3
    bne a0, t2, fail
    li t0, 0x00400513
    sw t0, 0(s2)
    fence
    jalr ra, 0(s2)
    li t2, 4
    bne a0, t2, fail

    li s1, 6
    sw s1, 0(s0)
    li s2, 0x80030000
    li t0, 5
    sw t0, 0(s2)
    lr.w t1, (s2)
    bne t0, t1, fail
    li t0, 7
    sc.w t1, t0, (s2)
    bnez t1, fail
    li t0, 3
    amoadd.w t1, t0, (s2)
    li t2, 7
    bne t1, t2, fail
    lw t1, 0(s2)
    li t2, 10
    bne t1, t2, fail
    lr.w t1, (s2)
    li t0, 11
    sw t0, 0(s2)
    li t0, 22
    sc.w t1, t0, (s2)
    li t2, 1
    bne t1, t2, fail
    lw t1, 0(s2)
    li t2, 11
    bne t1, t2, fail
    li s2, 0x87800000
    li t0, 5
    sw t0, 0(s2)
    lr.w t1, (s2)
    bne t0, t1, fail
    li t0, 7
    sc.w t1, t0, (s2)
    bnez t1, fail
    lw t1, 0(s2)
    bne t0, t1, fail

    li s1, 7
    sw s1, 0(s0)
    fence.i
    lw t0, 0x10(s0)
    li t1, 4
    bltu t0, t1, fail
    lw t0, 0x14(s0)
    li t1, 512
    bltu t0, t1, fail
    lw t0, 0x18(s0)
    bltu t0, t1, fail
    lw t0, 0x1c(s0)
    beqz t0, fail
    lw t0, 0x20(s0)
    beqz t0, fail
    lw t0, 0x24(s0)
    beqz t0, fail
    lw t0, 0x28(s0)
    bnez t0, fail
    li s1, 8
    sw s1, 0(s0)
    li t0, 0xc900600d
    sw t0, 4(s0)
    ebreak
fail:
    li t0, 0xc9ba0000
    or t0, t0, s1
    sw t0, 4(s0)
    ebreak
