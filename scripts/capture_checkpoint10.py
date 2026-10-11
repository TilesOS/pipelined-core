#!/usr/bin/env python3
"""Capture checkpoint 10 USB UART and exercise its physical receive interrupt."""
import argparse
import os
from pathlib import Path
import select
import sys
import termios
import time
import tty

READY = b"CHECKPOINT10 UART RX READY: send K\r\n"
MARKERS = (b"OpenSBI v1.7", b"CHECKPOINT10 SBI TIMER/PMP PASS\r\n",
           READY, b"CHECKPOINT10 UART RX/PLIC PASS\r\n")


def verify(data):
    cursor = 0
    for marker in MARKERS:
        found = data.find(marker, cursor)
        if found < 0:
            raise ValueError(f"missing serial milestone: {marker.decode().strip()}")
        cursor = found + len(marker)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("device", nargs="?", help="Linux USB UART device, e.g. /dev/ttyUSB1")
    parser.add_argument("--seconds", type=float, default=30)
    parser.add_argument("--output", type=Path, default=Path("build/checkpoint10-board/uart-first.dat"))
    parser.add_argument("--verify", type=Path, help="verify a previously saved boot capture")
    parser.add_argument("--trace", action="store_true", help="capture raw diagnostic bytes; press BTNC")
    args = parser.parse_args()
    if args.verify:
        try:
            verify(args.verify.read_bytes())
        except ValueError as exc:
            print(exc, file=sys.stderr)
            return 1
        print("PASS: OpenSBI, SBI timer/PMP and UART RX/PLIC serial milestones")
        return 0
    if not args.device or args.seconds <= 0:
        parser.error("device and positive --seconds are required")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(args.device, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    previous = termios.tcgetattr(fd)
    data, sent = bytearray(), False
    try:
        tty.setraw(fd)
        settings = termios.tcgetattr(fd)
        settings[4] = settings[5] = termios.B115200
        settings[2] |= termios.CLOCAL | termios.CREAD
        settings[2] &= ~termios.CRTSCTS
        termios.tcsetattr(fd, termios.TCSANOW, settings)
        termios.tcflush(fd, termios.TCIFLUSH)
        print("Serial ready at 115200 8N1. " +
              ("Press BTNC for the trace dump." if args.trace else "Press/release CPU RESET now."), flush=True)
        deadline = time.monotonic() + args.seconds
        while time.monotonic() < deadline:
            if not select.select([fd], [], [], min(0.25, max(0, deadline-time.monotonic())))[0]:
                continue
            try:
                chunk = os.read(fd, 4096)
            except BlockingIOError:
                continue
            data.extend(chunk)
            if not args.trace:
                sys.stdout.buffer.write(chunk)
                sys.stdout.buffer.flush()
                if not sent and READY in data:
                    # Only one byte, after the payload enabled its RX interrupt.
                    if os.write(fd, b"K") != 1:
                        raise OSError("UART challenge byte was not written")
                    sent = True
                try:
                    verify(data)
                except ValueError:
                    continue
                break
        args.output.write_bytes(data)
        print(f"\nCaptured {len(data)} bytes to {args.output}", flush=True)
    finally:
        termios.tcsetattr(fd, termios.TCSANOW, previous)
        os.close(fd)
    if args.trace:
        return 0
    try:
        verify(data)
    except ValueError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1
    print("PASS: OpenSBI, SBI timer/PMP and physical UART RX/PLIC")
    return 0


if __name__ == "__main__":
    sys.exit(main())
