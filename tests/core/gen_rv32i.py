#!/usr/bin/env python3
"""Generate reproducible dependency-heavy RV32I programs for Spike lockstep."""
import argparse
import random

parser = argparse.ArgumentParser()
parser.add_argument("--seed", type=int, required=True)
parser.add_argument("--count", type=int, default=400)
args = parser.parse_args()
rng = random.Random(args.seed)
regs = list(range(2, 26))
print(".option norvc\n.section .text\n.globl _start\n_start:")
print("lui x1, 0x80001")  # data starts outside the generated code
for reg in regs:
    print(f"addi x{reg}, x0, 0")
for index in range(args.count):
    rd = rng.choice(regs)
    rs1 = rng.choice(regs)
    rs2 = rng.choice(regs)
    op = rng.randrange(17)
    if op < 8:
        name = ("add", "sub", "sll", "slt", "sltu", "xor", "srl", "sra")[op]
        print(f"{name} x{rd}, x{rs1}, x{rs2}")
    elif op < 11:
        name = ("or", "and", "addi")[op - 8]
        if name == "addi":
            print(f"addi x{rd}, x{rs1}, {rng.randrange(-2048, 2048)}")
        else:
            print(f"{name} x{rd}, x{rs1}, x{rs2}")
    elif op < 14:
        name = ("slti", "sltiu", "xori")[op - 11]
        print(f"{name} x{rd}, x{rs1}, {rng.randrange(-2048, 2048)}")
    elif op == 14:
        name = rng.choice(("slli", "srli", "srai"))
        print(f"{name} x{rd}, x{rs1}, {rng.randrange(32)}")
    elif op == 15:
        name = rng.choice(("lb", "lbu", "lh", "lhu", "lw"))
        offset = rng.randrange(128)
        if name in ("lh", "lhu"):
            offset &= ~1
        elif name == "lw":
            offset &= ~3
        print(f"{name} x{rd}, {offset}(x1)")
    else:
        name = rng.choice(("sb", "sh", "sw"))
        offset = rng.randrange(128)
        if name == "sh":
            offset &= ~1
        elif name == "sw":
            offset &= ~3
        print(f"{name} x{rs2}, {offset}(x1)")
    if index % 19 == 18:
        # Exercise both redirect and fall-through after live dependencies.
        label = f"next_{index}"
        if rng.randrange(2):
            print(f"beq x{rd}, x{rd}, {label}")
            print("addi x27, x0, 99")
        else:
            print(f"bne x{rd}, x{rd}, {label}")
        print(f"{label}:")
print(".word 0xffffffff")
