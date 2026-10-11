#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo_root"
board_dir="$repo_root/build/checkpoint10-board"
mkdir -p "$board_dir"
# Reuse the exact pinned firmware/configuration tested by the simulation gate.
bash scripts/run_checkpoint10_opensbi.sh --build-only
riscv64-unknown-elf-gcc -march=rv32ima_zicsr_zifencei -mabi=ilp32 -nostdlib -Wl,--no-relax \
    -DBOARD_UART_TEST -T tests/privilege/opensbi_payload.ld \
    tests/privilege/opensbi_payload.S -o "$board_dir/payload.elf"
python3 - "$board_dir/payload.elf" <<'PY'
import subprocess, sys
data_labels = {'message', 'rx_ready', 'rx_pass'}
for line in subprocess.check_output(['riscv64-unknown-elf-nm', '-n', sys.argv[1]], text=True).splitlines():
    address, kind, name = line.split()
    if kind in ('T', 't') and name not in data_labels:
        assert int(address, 16) % 4 == 0, f'RV32 instruction label is misaligned: {line}'
PY
riscv64-unknown-elf-objcopy -O binary "$board_dir/payload.elf" "$board_dir/payload.bin"
python3 scripts/pack_checkpoint10_image.py \
    build/privilege/opensbi-gate/platform/generic/firmware/fw_jump.bin \
    "$board_dir/payload.bin" "$board_dir"
