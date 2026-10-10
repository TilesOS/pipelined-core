#!/usr/bin/env python3
"""Search or replay seeded hazard/trap schedules, with Spike checking every run."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

from report_cpu_coverage import summarize, format_report
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tests/core'))
from gen_hazard_traps import generate


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('raw_directory', type=Path)
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--replay', type=Path, help='Replay a frozen set of contributing seeds')
    args = parser.parse_args()
    baseline = summarize(args.raw_directory.glob('*.dat'))
    args.baseline.write_text(json.dumps(baseline, indent=2) + '\n')
    cases_dir = ROOT / 'build/coverage/seed-cases'
    cases_dir.mkdir(exist_ok=True)
    evidence = {'baseline_cross_hit': baseline['cross_hit'], 'cross_total': baseline['cross_total'],
                'baseline_percent': baseline['percent'], 'model_sha256': baseline['model_sha256'],
                'cases': [], 'cpu_bugs': 0}
    report = baseline

    def execute(seed, target, expected_source=None):
        nonlocal report
        hazard, exception, stage = target.split('_x_')
        name = f'seed_{seed}_{hazard}_{exception}_{stage}'
        source = cases_dir / f'{name}.S'
        elf, binary = source.with_suffix('.elf'), source.with_suffix('.bin')
        source.write_text(generate(seed, hazard, exception, stage))
        source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
        if expected_source and source_hash != expected_source:
            raise RuntimeError(f'seed {seed}: generated stimulus differs from the frozen manifest')
        subprocess.run([os.getenv('RISCV_GCC', 'riscv64-unknown-elf-gcc'),
                        '-march=rv32ima_zicsr_zifencei', '-mabi=ilp32', '-nostdlib',
                        '-Wl,--no-relax', '-T', str(ROOT / 'tests/lockstep/smoke.ld'),
                        str(source), '-o', str(elf)], check=True)
        subprocess.run([os.getenv('RISCV_OBJCOPY', 'riscv64-unknown-elf-objcopy'),
                        '-O', 'binary', str(elf), str(binary)], check=True)
        env = dict(os.environ, CORE_IMAGE=str(binary), CPU_COVERAGE_DIR=str(args.raw_directory.resolve()))
        log = source.with_suffix('.out')
        with log.open('w') as output:
            result = subprocess.run([sys.executable, str(ROOT / 'scripts/lockstep.py'),
                '--spike', os.getenv('SPIKE_BIN', str(ROOT / 'build/tools/spike/bin/spike')),
                '--dut', str(ROOT / 'build/core/obj_dir/Vcheckpoint4_top'),
                '--elf', str(elf), '--limit', '100', '--until-trap'],
                env=env, stdout=output, stderr=subprocess.STDOUT)
        if result.returncode:
            evidence['cases'].append({'seed': seed, 'target': target, 'status': 'failed',
                                      'log': str(log.relative_to(ROOT))})
            args.output.write_text(json.dumps(evidence, indent=2) + '\n')
            raise RuntimeError(f'seed {seed} failed; inspect {log} before claiming any bug or coverage')
        updated = summarize(args.raw_directory.glob('*.dat'))
        before = set(report['groups']['hazard_trap_stage']['uncovered'])
        after = set(updated['groups']['hazard_trap_stage']['uncovered'])
        gained = sorted(before - after)
        events = int(re.search(r'PASS: (\d+) architectural events', log.read_text())[1])
        evidence['cases'].append({'seed': seed, 'target': target, 'status': 'passed',
            'new_bins': gained, 'cross_hit_after': updated['cross_hit'],
            'source': str(source.relative_to(ROOT)), 'source_sha256': source_hash,
            'spike_checked_events': events})
        report = updated
        print(f"seed {seed}: +{len(gained)} cross bins; {report['cross_hit']}/{report['cross_total']}", flush=True)
        args.output.write_text(json.dumps(evidence, indent=2) + '\n')
        return after

    if args.replay:
        manifest = json.loads(args.replay.read_text())
        if manifest['model_sha256'] != baseline['model_sha256']:
            raise RuntimeError('seed manifest belongs to a different coverage model')
        for case in manifest['seeds']:
            execute(case['seed'], case['target'], case['source_sha256'])
    else:
        targets = list(report['groups']['hazard_trap_stage']['uncovered'])
        seed = 1000
        for target in targets:
            if target not in report['groups']['hazard_trap_stage']['uncovered']:
                continue
            for attempt in range(32):
                after = execute(seed, target)
                seed += 1
                if target not in after:
                    break
            else:
                raise RuntimeError(f'target {target} remains unhit after 32 seeds')
    evidence.update({'final_cross_hit': report['cross_hit'], 'final_percent': report['percent'],
                     'scenarios_closed': report['cross_hit'] - baseline['cross_hit'],
                     'seed_runs': len(evidence['cases'])})
    args.output.write_text(json.dumps(evidence, indent=2) + '\n')
    print(format_report(report), end='')
    if report['cross_hit'] != report['cross_total']:
        raise RuntimeError('cross coverage remains incomplete')


if __name__ == '__main__':
    main()
