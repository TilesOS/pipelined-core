#!/usr/bin/env python3
"""Decode a checkpoint 9 board-test UART capture; exit 0 only for a full pass."""
import argparse
from pathlib import Path
import struct
import sys

MAGIC = b'C9SM\x01'
PACKET_BYTES = 61

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('capture', type=Path)
    args = parser.parse_args()
    data = args.capture.read_bytes()
    offset = data.rfind(MAGIC)
    while offset >= 0 and offset + PACKET_BYTES > len(data):
        offset = data.rfind(MAGIC, 0, offset)
    if offset < 0:
        print('No complete C9SM v1 packet in capture', file=sys.stderr)
        return 1
    flags, phase, result, pc, cause, tval, imiss, dmiss, dwb, ibypass, dbypass, trips, errors, cycles = \
        struct.unpack_from('<14I', data, offset + len(MAGIC))
    print(f'calibrated={bool(flags & 1)} ready={bool(flags & 2)} halted={bool(flags & 4)} passed={bool(flags & 8)}')
    print(f'phase={phase} result=0x{result:08x} last_pc=0x{pc:08x} cause={cause} tval=0x{tval:08x}')
    print(f'I misses={imiss}; D misses={dmiss}; D writebacks={dwb}; I/D bypasses={ibypass}/{dbypass}')
    print(f'DMA trips={trips}; DMA errors={errors}; cycles={cycles} ({cycles / 50_000_000:.6f} s at 50 MHz)')
    good = (flags == 15 and phase == 8 and result == 0xc900600d and cause == 3 and
            imiss >= 4 and dmiss >= 512 and dwb >= 512 and ibypass and dbypass and trips and not errors)
    print('PASS: checkpoint 9 board smoke test' if good else 'INCOMPLETE/FAIL: retain this capture for diagnosis')
    return 0 if good else 2

if __name__ == '__main__':
    raise SystemExit(main())
