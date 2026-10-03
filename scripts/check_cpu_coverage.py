#!/usr/bin/env python3
"""Exercise counter collection with real fault/divider/multi-instance DUT runs."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

from report_cpu_coverage import expected_bins, read_counts, summarize

ROOT = Path(__file__).resolve().parents[1]
DUT = ROOT / 'build/core/obj_dir/Vcheckpoint4_top'


def run(image, directory, option=None):
    env = dict(os.environ, CORE_IMAGE=str(ROOT / f'build/core/{image}.bin'),
               CPU_COVERAGE_DIR=str(directory))
    if option:
        subprocess.run([str(DUT), option], env=env, check=True)
    else:
        with subprocess.Popen([str(DUT)], env=env, stdin=subprocess.PIPE,
                              stdout=subprocess.PIPE, text=True) as process:
            for _ in range(1000):
                process.stdin.write('step\n')
                process.stdin.flush()
                event = json.loads(process.stdout.readline())
                if event['kind'] == 'retire' and event['trap']:
                    break
            else:
                process.kill()
                raise AssertionError(f'{image}: no trap')
            # Stop on the final trap itself, without an extra sampling cycle.
            process.stdin.write('quit\n')
            process.stdin.flush()
            assert process.wait(timeout=5) == 0
    return summarize(directory.glob('*.dat'))


def main():
    with tempfile.TemporaryDirectory(prefix='selftest-', dir=ROOT / 'build/coverage') as temp:
        base = Path(temp)
        for name in ('fault', 'divide', 'contention'):
            (base / name).mkdir()
        fault = run('exception_load_access', base / 'fault')
        assert fault['groups']['trap']['bins']['load_access'] == 1
        assert fault['groups']['instruction']['bins']['lw'] == 0
        assert fault['groups']['instruction']['bins']['sw'] == 1
        assert fault['groups']['memory']['bins']['lw_lane0'] == 0
        divide = run('m_directed', base / 'divide')
        assert all(count == 1 for count in divide['groups']['divide']['bins'].values())
        contention = run('atomic_contention', base / 'contention', '--contention-test')
        assert contention['files'] == 3  # two active models plus the unused main model
        assert contention['groups']['sc']['bins'] == {'failure': 1, 'success': 1}
        assert contention['groups']['instruction']['bins']['lr_w'] == 2
        files = list((base / 'fault').glob('*.dat'))
        assert summarize(files + files) == fault  # don't double-count repeated paths
        corrupt = base / 'incomplete.dat'
        corrupt.write_text('\n'.join(files[0].read_text().splitlines()[:-1]) + '\n')
        try:
            read_counts(corrupt, expected_bins())
        except ValueError:
            pass
        else:
            raise AssertionError('incomplete counter data was accepted')
    print('PASS: final trap sampled; faulting loads excluded; divide operands classified; '
          'model lifetimes isolated; incomplete coverage rejected')


if __name__ == '__main__':
    main()
