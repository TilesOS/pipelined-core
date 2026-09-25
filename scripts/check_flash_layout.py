#!/usr/bin/env python3
"""Check the frozen QSPI partition budget and measured build artifacts."""

import argparse
import json
from pathlib import Path
import sys

LAYOUT = Path(__file__).resolve().parents[1] / "config" / "flash-layout.json"


def check_layout(layout):
    flash_bytes = layout["flash_bytes"]
    minimum_spare = layout["minimum_spare_bytes"]
    end = 0
    seen = set()
    for region in layout["regions"]:
        name, offset, capacity = (region[key] for key in ("name", "offset", "capacity"))
        if name in seen or offset != end or capacity <= 0:
            raise ValueError(f"invalid region order, gap, overlap, or capacity: {name}")
        seen.add(name)
        end = offset + capacity
        if end > flash_bytes:
            raise ValueError(f"{name} exceeds flash")
    spare = flash_bytes - end
    if spare < minimum_spare:
        raise ValueError(f"only {spare} bytes spare; minimum is {minimum_spare}")
    return spare


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--asset", action="append", default=[], metavar="NAME=PATH",
                        help="measured artifact; provide each region except manifest")
    args = parser.parse_args()
    layout = json.loads(LAYOUT.read_text())
    spare = check_layout(layout)
    regions = {region["name"]: region for region in layout["regions"]}
    print(f"Flash: {layout['flash_bytes']:,} bytes; reserved: "
          f"{layout['flash_bytes'] - spare:,}; spare: {spare:,} bytes")
    for region in layout["regions"]:
        print(f"  {region['name']:12} 0x{region['offset']:06x}.."
              f"0x{region['offset'] + region['capacity'] - 1:06x} "
              f"({region['capacity']:,} bytes)")
    if not args.asset:
        print("BUDGET ONLY: no built artifacts were supplied")
        return 0
    assets = {}
    for entry in args.asset:
        if "=" not in entry:
            parser.error(f"expected NAME=PATH: {entry}")
        name, path = entry.split("=", 1)
        if name not in regions or name == "manifest" or name in assets:
            parser.error(f"unknown or repeated asset: {name}")
        assets[name] = Path(path)
    required = set(regions) - {"manifest"}
    if set(assets) != required:
        parser.error(f"need exactly {', '.join(sorted(required))}")
    failed = False
    for name, path in assets.items():
        if not path.is_file():
            print(f"FAIL {name}: missing {path}", file=sys.stderr)
            failed = True
            continue
        size = path.stat().st_size
        capacity = regions[name]["capacity"]
        if size == 0 or size > capacity:
            print(f"FAIL {name}: {size:,} bytes, limit {capacity:,}", file=sys.stderr)
            failed = True
        else:
            print(f"PASS {name}: {size:,}/{capacity:,} bytes")
    if failed:
        return 1
    print("PASS: all measured artifacts fit; at least 2.5 MiB remains unused")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, TypeError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        sys.exit(1)
