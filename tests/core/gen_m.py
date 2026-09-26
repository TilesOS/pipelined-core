#!/usr/bin/env python3
"""Seeded RV32M arithmetic and dependency lockstep program."""
import argparse
import random

parser = argparse.ArgumentParser()
parser.add_argument("--seed", type=int, required=True)
parser.add_argument("--count", type=int, default=200)
args = parser.parse_args()
rng = random.Random(args.seed)
regs = list(range(2, 26))
print(".option norvc\n.section .text\n.globl _start\n_start:")
for reg in regs:
    print(f"addi x{reg}, x0, 0")
print("lui x2, 0x80000")
print("addi x3, x0, -1")
for _ in range(args.count):
    rd, rs1, rs2 = (rng.choice(regs) for unused in range(3))
    choice = rng.randrange(12)
    if choice < 8:
        op = ("mul", "mulh", "mulhsu", "mulhu", "div", "divu", "rem", "remu")[choice]
        print(f"{op} x{rd}, x{rs1}, x{rs2}")
    elif choice == 8:
        print(f"addi x{rd}, x{rs1}, {rng.randrange(-2048, 2048)}")
    elif choice == 9:
        print(f"xor x{rd}, x{rs1}, x{rs2}")
    elif choice == 10:
        print(f"srai x{rd}, x{rs1}, {rng.randrange(32)}")
    else:
        print(f"lui x{rd}, {rng.randrange(1 << 20)}")
print(".word 0xffffffff")
