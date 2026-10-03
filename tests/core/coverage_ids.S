// Implementation-defined machine IDs are checked locally, as in counter tests.
.option norvc
.section .text
.globl _start
_start:
    csrr x1, marchid
    csrr x2, mimpid
    ebreak
