#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"
build_dir="$repo_root/build/checkpoint9-board"
cross_gcc=${RISCV_GCC:-riscv64-unknown-elf-gcc}
cross_objcopy=${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy}
mkdir -p "$build_dir"
"$cross_gcc" -march=rv32ima_zicsr_zifencei -mabi=ilp32 -nostdlib \
    -Wl,--no-relax -T tests/board/checkpoint9_smoke.ld \
    tests/board/checkpoint9_smoke.S -o "$build_dir/checkpoint9_smoke.elf"
"$cross_objcopy" -O binary "$build_dir/checkpoint9_smoke.elf" "$build_dir/checkpoint9_smoke.bin"
python3 - "$build_dir" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
data = (root / 'checkpoint9_smoke.bin').read_bytes()
assert len(data) <= 8192 and len(data) % 4 == 0, 'ROM must fit 8 KiB and contain full words'
data += b'\xff' * (8192 - len(data))
(root / 'checkpoint9_smoke.mem').write_text(''.join(
    f'{int.from_bytes(data[i:i+4], "little"):08x}\n' for i in range(0, 8192, 4)))
print(f'Checkpoint 9 ROM: {len(data)} bytes padded; program {(root / "checkpoint9_smoke.bin").stat().st_size} bytes')
PY
if [[ ${1:-} == --update ]]; then
    mkdir -p config/rom
    cp "$build_dir/checkpoint9_smoke.mem" config/rom/checkpoint9_smoke.mem
else
    cmp "$build_dir/checkpoint9_smoke.mem" config/rom/checkpoint9_smoke.mem
    echo 'PASS: committed ROM matches assembly source'
fi
