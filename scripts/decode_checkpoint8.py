#!/usr/bin/env python3
"""Decode the repeated checkpoint 8 UART measurement packet."""

import argparse
import struct
import sys
from pathlib import Path

MAGIC = b"D8BM\x01"
PACKET_BYTES = len(MAGIC) + 7 * 4
SWEEP_BYTES = 256 * 16 * 16
CORE_HZ = 50_000_000


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", type=Path, help="raw UART capture file")
    args = parser.parse_args()
    data = args.capture.read_bytes()
    offset = data.rfind(MAGIC)
    while offset >= 0 and offset + PACKET_BYTES > len(data):
        offset = data.rfind(MAGIC, 0, offset)
    if offset < 0:
        print("No complete D8BM v1 packet in capture", file=sys.stderr)
        return 1
    base_w, base_r, cont_w, cont_r, dma_err, cpu_err, cpu_trips = struct.unpack_from(
        "<7I", data, offset + len(MAGIC)
    )
    print(f"packet offset: {offset}, core clock: {CORE_HZ:,} Hz")
    for label, cycles in (
        ("baseline write", base_w),
        ("baseline read", base_r),
        ("contended write", cont_w),
        ("contended read", cont_r),
    ):
        mbps = SWEEP_BYTES * CORE_HZ / cycles / 1_000_000 if cycles else 0
        print(f"{label:16s} {cycles:10,d} cycles  {mbps:8.2f} MB/s")
    print(f"DMA errors: {dma_err}; CPU-like errors: {cpu_err}; CPU-like round trips: {cpu_trips}")
    return 0 if dma_err == 0 and cpu_err == 0 and all((base_w, base_r, cont_w, cont_r)) else 2


if __name__ == "__main__":
    raise SystemExit(main())
