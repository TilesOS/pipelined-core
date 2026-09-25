#!/usr/bin/env python3
"""Decode checkpoint-4 TRCE packets captured from the debug UART."""

import argparse
from pathlib import Path
import struct
import sys


def decode(data):
    cursor = 0
    packets = 0
    while True:
        start = data.find(b"TRCE", cursor)
        if start < 0:
            break
        if len(data) - start < 6:
            raise ValueError(f"truncated TRCE header at byte {start}")
        count = struct.unpack_from("<H", data, start + 4)[0]
        if count > 256:
            raise ValueError(f"invalid record count {count} at byte {start}")
        end = start + 6 + 17 * count
        if len(data) < end:
            raise ValueError(f"truncated packet at byte {start}: need {end} bytes")
        print(f"packet {packets}: {count} records")
        for index in range(count):
            pc, insn, cause, tval, meta = struct.unpack_from(
                "<IIIIB", data, start + 6 + 17 * index
            )
            kind = "trap" if meta & 4 else "retire"
            print(f"{index:03d} {kind:6} priv={meta & 3} "
                  f"pc=0x{pc:08x} insn=0x{insn:08x} "
                  f"cause=0x{cause:08x} tval=0x{tval:08x}")
        packets += 1
        cursor = end
    if packets == 0:
        raise ValueError("no complete TRCE packet found")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", nargs="?", type=Path,
                        help="raw UART byte capture; default is standard input")
    args = parser.parse_args()
    data = args.capture.read_bytes() if args.capture else sys.stdin.buffer.read()
    try:
        decode(data)
    except ValueError as exc:
        print(f"trace decode error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
