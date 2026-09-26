    .option norvc
    .section .text
    .globl _start
_start:
    lui x1, 0x80001
    auipc x2, 0
    addi x3, x0, -1
    addi x0, x3, 1
    slti x4, x3, 0
    sltiu x5, x3, 1
    xori x6, x3, 0x55
    ori x7, x0, 0x12
    andi x8, x3, 0x33
    slli x9, x8, 3
    srli x10, x3, 4
    srai x11, x3, 4
    add x12, x9, x8
    sub x13, x12, x8
    sll x14, x8, x4
    slt x15, x3, x4
    sltu x16, x3, x4
    xor x17, x6, x7
    srl x18, x3, x4
    sra x19, x3, x4
    or x20, x6, x7
    and x21, x6, x7
    addi x22, x0, 0x7f
    sb x22, 1(x1)
    lb x23, 1(x1)
    lbu x24, 1(x1)
    addi x22, x0, -128
    sb x22, 2(x1)
    lb x23, 2(x1)
    lbu x24, 2(x1)
    addi x22, x0, -1
    sh x22, 2(x1)
    lh x23, 2(x1)
    lhu x24, 2(x1)
    sw x3, 4(x1)
    lw x25, 4(x1)
    sb x0, 5(x1)
    lw x26, 4(x1)
    sh x8, 6(x1)
    lw x27, 4(x1)
    sw x27, 8(x1)
    lw x28, 8(x1)
    fence
    beq x3, x3, 1f
    addi x29, x0, 99
1:  bne x3, x4, 2f
    addi x29, x0, 99
2:  blt x3, x4, 3f
    addi x29, x0, 99
3:  bge x4, x3, 4f
    addi x29, x0, 99
4:  bltu x4, x3, 5f
    addi x29, x0, 99
5:  bgeu x3, x4, 6f
    addi x29, x0, 99
6:  beq x3, x4, 7f
    addi x29, x0, 1
7:  jal x30, 8f
    addi x29, x0, 99
8:  auipc x31, 0
    addi x31, x31, 17   // JALR clears bit zero
    jalr x30, 0(x31)
    addi x29, x0, 99
    addi x29, x29, 1
    .word 0xffffffff
