#!/usr/bin/env python3
"""Print compact Vivado evidence for review; does not waive diagnostics."""
import argparse
from collections import Counter
from pathlib import Path
import re

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("directory", nargs="?", type=Path,
                    default=Path(__file__).resolve().parents[1] /
                    "build/checkpoint9-board/vivado-reports")
args = parser.parse_args()


def read(name):
    path = args.directory / name
    if not path.is_file():
        parser.error(f"missing report: {path}")
    return path.read_text(errors="replace").splitlines()


print("TIMING (full details retained in timing_summary.rpt)")
timing = read("timing_summary.rpt")
for index, line in enumerate(timing):
    if "Design Timing Summary" in line and line.lstrip().startswith("|"):
        print("\n".join(timing[index:index + 15]))
        break

print("\nROUTED RESOURCES")
for line in read("utilization.rpt"):
    if re.match(r"\|\s*(Slice LUTs|Slice Registers|Slice|Block RAM Tile|"
                r"RAMB36/FIFO\*?|RAMB18\*?|DSPs|DSP48E1)\s*\|", line):
        print(line)

print("\nCLOCK PERIODS")
for line in read("clocks.rpt"):
    fields = line.split()
    if fields and fields[0] in {"board_clk_100", "clk50_unbuffered",
                               "clk200_unbuffered", "clk_pll_i"}:
        print(f"{fields[0]}: {fields[1]} ns")

for name in ("methodology.rpt", "drc.rpt"):
    print(f"\n{name} RULE COUNTS (original severities)")
    for line in read(name):
        if re.match(r"\|\s*[A-Z]+[A-Z0-9]*-\d+\s*\|", line):
            print(line)

print("\nCDC RULE COUNTS (original severities)")
cdc = read("cdc.rpt")
expected_rows = Counter()
for line in cdc:
    match = re.match(r"(CDC-\d+)\s+(Critical|Warning|Info)\s+(\d+)", line)
    if match:
        print(line)
        expected_rows[match.group(1)] = int(match.group(3))

# Group all detail rows by source, including paths beyond the report's first
# screen. These are endpoint inventories, not an automatic safety decision.
groups = Counter()
examples = {}
other = []
actual_rows = Counter()
for line in cdc:
    match = re.match(r"\s*\d+\s+(CDC-\d+)\s+(Critical|Warning|Info)\s+", line)
    if not match:
        continue
    rule = match.group(1)
    actual_rows[rule] += 1
    fields = line.split()
    source, destination = fields[-2:]
    fifo = re.search(r"/crossing/(\w+_fifo)/", source)
    if fifo and "/storage_reg" in source:
        family = f"{fifo.group(1)} payload storage"
    elif fifo and re.search(r"/(wr|rd)_gray_reg", source):
        family = f"{fifo.group(1)} Gray pointer"
    elif "/bus/link_rst_n_reg/" in source:
        family = "registered link reset"
    elif "/calib_ui_reg/" in source:
        family = "registered UART calibration status"
    elif source.startswith("mig/") or destination.startswith("mig/"):
        family = "generated MIG endpoints (review separately)"
    else:
        family = "OTHER (review required)"
        other.append(line)
    key = rule, family
    groups[key] += 1
    examples.setdefault(key, (source, destination))

print("\nCDC SOURCE GROUPS (available detail rows)")
for (rule, family), count in sorted(groups.items()):
    print(f"{rule}: {count} {family}")
print("\nCDC EXAMPLE ENDPOINTS")
for key in sorted(examples):
    if key[0] in {"CDC-10", "CDC-11", "CDC-13"} or "OTHER" in key[1]:
        source, destination = examples[key]
        print(f"{key[0]} {key[1]}: {source} -> {destination}")
if other:
    print(f"\nOTHER detail rows: {len(other)}; first 10:")
    print("\n".join(other[:10]))
if actual_rows != expected_rows:
    print("\nCDC INVENTORY INCOMPLETE OR AGGREGATED: detail rows differ from summary counts.")
    for rule in sorted(expected_rows.keys() | actual_rows.keys()):
        if actual_rows[rule] != expected_rows[rule]:
            print(f"{rule}: {actual_rows[rule]} detail rows; {expected_rows[rule]} summary count")
print("\nReview full reports for path details and constraint coverage before signoff.")
