#!/usr/bin/env python3
"""Targeted random trap programs for measured hazard/stage holes.

Templates target the desired trap, blocking mechanism and occupied stage.
Seeds vary physical registers, values, independent scheduling gaps and RAW
producer operations through uniform random choices, without SV constraint blocks
or weighted instruction generation. A requested tuple is credited only by actual
RTL coverage.
"""
import argparse
from pathlib import Path
import random

CAUSES = {'instruction_misaligned': 0, 'instruction_access': 1,
          'illegal_instruction': 2, 'breakpoint': 3, 'load_misaligned': 4,
          'load_access': 5, 'store_misaligned': 6, 'store_access': 7, 'machine_ecall': 11}


def generate(seed, hazard, exception, stage):
    rng = random.Random(seed)
    base, value, result, source, quotient, consumer, scratch = rng.sample(range(1, 28), 7)
    register = lambda n: f'x{n}'
    b, v, r, src, q, c, tmp = map(register, (base, value, result, source, quotient, consumer, scratch))
    # Defined inputs avoid incidental divide-by-zero/overflow and misalignment;
    # only the selected fault terminates the architectural trace.
    setup = [f'lui {b}, 0x80001', f'addi {v}, x0, {rng.randrange(3, 200)}',
             f'addi {src}, x0, {rng.randrange(201, 1000)}', f'sw {v}, 0({b})']
    for _ in range(rng.randrange(0, 5)):
        setup.append(f'addi {tmp}, x0, {rng.randrange(-2048, 2048)}')
    # Fault operands are initialized before the timed prefix. RAW/ID cases
    # overwrite exactly the operand that the faulting instruction consumes.
    if exception == 'instruction_misaligned':
        setup += [f'lui {b}, 0x80000', f'addi {b}, {b}, 2']
        fault = f'jalr {r}, 0({b})'
    elif exception == 'instruction_access':
        fault = None  # fall off the 64 KiB memory boundary after the timed prefix
    elif exception == 'illegal_instruction':
        fault = f'.word 0x{(0x40001013 | (base << 15) | (result << 7)):08x}'
    elif exception == 'breakpoint':
        fault = 'ebreak'
    elif exception == 'machine_ecall':
        fault = 'ecall'
    elif exception in ('load_misaligned', 'store_misaligned'):
        fault = f'lw {r}, 2({b})' if exception.startswith('load') else f'sw {v}, 2({b})'
    else:
        setup += [f'lui {b}, 0x80010']
        fault = f'lw {r}, 0({b})' if exception.startswith('load') else f'sw {v}, 0({b})'
    # Variable spacing is real instruction scheduling, not direct counter writes.
    gap = rng.randrange(3)
    nop = f'addi {tmp}, x0, {rng.randrange(-2048, 2048)}'
    if hazard == 'divider_busy':
        prefix = [f'div {q}, {src}, {v}']
        prefix += [nop] * (1 + gap if stage == 'fetch_stage' else gap)
    elif hazard == 'serialization':
        prefix = [f'csrrw {q}, mscratch, {v}']
        prefix += [nop] * (1 + gap if stage == 'fetch_stage' else gap)
    elif hazard == 'raw_dependency':
        if stage == 'fetch_stage':
            producer = rng.choice([f'addi {q}, {v}, {rng.randrange(1, 100)}',
                                   f'mul {q}, {v}, {src}', f'lw {q}, 0({b})'])
            # Access-fault operands use an inaccessible base, so the timed RAW
            # producer must not load through that base.
            if exception.endswith('access') or exception == 'instruction_misaligned':
                producer = f'addi {q}, {v}, {rng.randrange(1, 100)}'
            prefix = [producer] + [nop] * gap + [f'addi {c}, {q}, {rng.randrange(1, 100)}']
        else:
            if exception in ('breakpoint', 'machine_ecall', 'instruction_access'):
                raise ValueError('structurally excluded RAW/ID target')
            if exception == 'instruction_misaligned':
                producer = f'addi {b}, {b}, 0'
            elif exception.endswith('access') or exception == 'instruction_misaligned':
                producer = f'lui {b}, 0x80010'
            elif exception.endswith('misaligned'):
                producer = f'lui {b}, 0x80001'
            else:
                producer = rng.choice([f'addi {b}, {v}, {rng.randrange(1, 100)}',
                                       f'mul {b}, {v}, {src}'])
            prefix = [producer] + [nop] * gap
    else:
        raise ValueError(hazard)
    lines = ['.option norvc', '.section .text', '.globl _start', '_start:'] + setup
    if fault is None:
        lines += ['jal x0, boundary_prefix', f'.org {65536 - 4 * len(prefix)}', 'boundary_prefix:']
    lines += prefix
    if fault:
        lines += [fault, f'sw {src}, 4({b})', '.word 0xffffffff']
    return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--seed', type=int, required=True)
    parser.add_argument('--hazard', choices=('raw_dependency', 'serialization', 'divider_busy'), required=True)
    parser.add_argument('--exception', choices=CAUSES, required=True)
    parser.add_argument('--stage', choices=('fetch_stage', 'decode_stage'), required=True)
    args = parser.parse_args()
    print(generate(args.seed, args.hazard, args.exception, args.stage), end='')


if __name__ == '__main__':
    main()
