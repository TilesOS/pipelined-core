#!/usr/bin/env python3
"""Capture 115200-baud 8N1 board reports on Linux without third-party packages."""
import argparse
import os
from pathlib import Path
import select
import termios
import time
import tty

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('device', help='USB serial device, e.g. /dev/ttyUSB1')
    parser.add_argument('--seconds', type=float, default=5)
    parser.add_argument('--output', type=Path, default=Path('build/checkpoint9-board/uart-capture.dat'))
    args = parser.parse_args()
    if args.seconds <= 0:
        parser.error('--seconds must be positive')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(args.device, os.O_RDONLY | os.O_NOCTTY | os.O_NONBLOCK)
    previous = termios.tcgetattr(fd)
    try:
        tty.setraw(fd)
        settings = termios.tcgetattr(fd)
        settings[4] = settings[5] = termios.B115200
        settings[2] |= termios.CLOCAL | termios.CREAD
        settings[2] &= ~termios.CRTSCTS
        termios.tcsetattr(fd, termios.TCSANOW, settings)
        termios.tcflush(fd, termios.TCIFLUSH)
        data = bytearray()
        deadline = time.monotonic() + args.seconds
        while time.monotonic() < deadline:
            if select.select([fd], [], [], min(0.25, max(0, deadline-time.monotonic())))[0]:
                try:
                    data.extend(os.read(fd, 4096))
                except BlockingIOError:
                    pass
        args.output.write_bytes(data)
        print(f'Captured {len(data)} bytes to {args.output}')
    finally:
        termios.tcsetattr(fd, termios.TCSANOW, previous)
        os.close(fd)

if __name__ == '__main__':
    main()
