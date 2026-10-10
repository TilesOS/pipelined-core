#!/usr/bin/env python3
"""Merge named SV covergroup bins; reject incomplete or mismatched data."""
import argparse
from collections import defaultdict
import hashlib
from functools import lru_cache
import json
from pathlib import Path
import re

MODEL = Path(__file__).resolve().parents[1] / 'tests/core/cpu_coverage.sv'


@lru_cache(maxsize=4)
def cross_partitions(model=MODEL):
    partitions = {}
    for group, body in re.findall(r'covergroup (\w+)_cg;(.*?)endgroup', model.read_text(), re.S):
        if 'scenario: cross' not in body:
            continue
        dimensions = []
        for cp, cp_body in re.findall(r'(\w+): coverpoint \w+ \{(.*?)\n        \}', body, re.S):
            dimensions.append(re.findall(r'\bbins (\w+)\s*=', cp_body))
        from itertools import product
        partitions[group] = {'_x_'.join(values) for values in product(*dimensions)}
    return partitions


def expected_bins(model=MODEL):
    groups = {}
    for group, body in re.findall(r'covergroup (\w+)_cg;(.*?)endgroup', model.read_text(), re.S):
        if 'scenario: cross' in body:
            continue  # component coverpoints do not inflate the cross denominator
        groups[group] = re.findall(r'\bbins (\w+)\s*=', body)
    if not groups or any(not bins for bins in groups.values()):
        raise ValueError('coverage model has no explicit bins')
    expected = {(group, name) for group, bins in groups.items() for name in bins}
    for bins in cross_partitions(model).values():
        expected.update(('hazard_trap_stage', name) for name in bins)
    return expected


def read_counts(path, expected):
    counts = defaultdict(int)
    for line in path.read_text().splitlines():
        if not line.startswith('C '):
            continue
        match = re.fullmatch(r"C '(.*)' ([0-9]+)", line)
        if not match:
            raise ValueError(f'{path}: malformed coverage record')
        fields = dict(field.split('\x02', 1) for field in match[1].split('\x01')[1:])
        if fields.get('t') != 'covergroup' or Path(fields.get('f', '')).name != MODEL.name:
            continue
        group = fields['page'].removeprefix('v_covergroup/').removesuffix('_cg')
        if group in cross_partitions():
            if fields.get('cross') != '1':
                continue
            if fields['bin'] not in cross_partitions()[group]:
                raise ValueError(f'{path}: cross bin outside its declared partition')
            group = 'hazard_trap_stage'
        key = (group, fields['bin'])
        if key not in expected:
            raise ValueError(f'{path}: unexpected bin {key}')
        counts[key] += int(match[2])
    missing = expected - counts.keys()
    if missing:
        raise ValueError(f'{path}: missing {len(missing)} model bins')
    return dict(counts)


def summarize(files, model=MODEL):
    expected = expected_bins(model)
    counts = defaultdict(int)
    files = sorted({path.resolve() for path in files})
    if not files:
        raise ValueError('no coverage files; run the instrumented regression first')
    for path in files:
        for key, count in read_counts(path, expected).items():
            counts[key] += count
    groups = {}
    for group in sorted({group for group, _ in expected}):
        bins = {name: counts[group, name] for g, name in sorted(expected) if g == group}
        hit = sum(count > 0 for count in bins.values())
        groups[group] = {'hit': hit, 'total': len(bins), 'bins': bins,
                         'uncovered': [name for name, count in bins.items() if count == 0]}
    hit = sum(count > 0 for count in counts.values())
    cross = groups.get('hazard_trap_stage', {'hit': 0, 'total': 0})
    return {'cross_hit': cross['hit'], 'cross_total': cross['total'],
            'cross_percent': 100 * cross['hit'] / cross['total'] if cross['total'] else 0,
            'model_sha256': hashlib.sha256(model.read_bytes()).hexdigest(),
            'files': len(files), 'hit': hit, 'total': len(expected),
            'percent': 100 * hit / len(expected), 'groups': groups}


def format_report(report):
    lines = [f"CPU functional coverage: {report['hit']}/{report['total']} bins "
             f"({report['percent']:.2f}%)", f"Merged {report['files']} simulation files; hit threshold: 1"]
    lines.append(f"Hazard × trap × stage cross: {report['cross_hit']}/{report['cross_total']} "
                 f"({report['cross_percent']:.2f}%); 84 structurally excluded tuples")
    for group, data in report['groups'].items():
        lines.append(f"  {group}: {data['hit']}/{data['total']}")
        if data['uncovered']:
            lines.append('    uncovered: ' + ', '.join(data['uncovered']))
    return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('--json', type=Path)
    parser.add_argument('--min-percent', type=float, default=0)
    args = parser.parse_args()
    try:
        report = summarize(args.directory.glob('*.dat'))
    except (ValueError, KeyError) as exc:
        parser.exit(1, f'coverage error: {exc}\n')
    print(format_report(report), end='')
    if args.json:
        args.json.write_text(json.dumps(report, indent=2) + '\n')
    if report['percent'] < args.min_percent:
        parser.exit(1, f'coverage below required {args.min_percent:.2f}%\n')


if __name__ == '__main__':
    main()
