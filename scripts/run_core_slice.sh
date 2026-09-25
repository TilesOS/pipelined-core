#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"
build_dir="$repo_root/build/core"
spike_bin=${SPIKE_BIN:-"$repo_root/build/tools/spike/bin/spike"}
cross_gcc=${RISCV_GCC:-riscv64-unknown-elf-gcc}
cross_objcopy=${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy}
verilator_bin=${VERILATOR_BIN:-verilator}
for tool in "$cross_gcc" "$cross_objcopy" "$verilator_bin"; do
    command -v "$tool" >/dev/null || { echo "missing tool: $tool" >&2; exit 1; }
done
[[ -x "$spike_bin" ]] || { echo "Spike missing: $spike_bin" >&2; exit 1; }
mkdir -p "$build_dir"
"$cross_gcc" -march=rv32ima_zicsr_zifencei -mabi=ilp32 -nostdlib \
    -Wl,--no-relax -T tests/lockstep/smoke.ld tests/lockstep/smoke.S \
    -o "$build_dir/smoke.elf"
"$cross_objcopy" -O binary "$build_dir/smoke.elf" "$build_dir/smoke.bin"
if ! "$verilator_bin" --cc --exe --build --top-module checkpoint4_top \
    --Mdir "$build_dir/obj_dir" -Wall -Wno-fatal \
    "$repo_root/rtl/core/rv32_slice.sv" \
    "$repo_root/rtl/debug/uart_tx_byte.sv" \
    "$repo_root/rtl/debug/trace_ring_uart.sv" \
    "$repo_root/rtl/top/checkpoint4_top.sv" \
    "$repo_root/tests/core/core_main.cpp" \
    > "$build_dir/verilator-build.log" 2>&1; then
    echo "Verilator CPU build failed; final log lines:" >&2
    tail -100 "$build_dir/verilator-build.log" >&2
    exit 1
fi
export CORE_IMAGE="$build_dir/smoke.bin"
python3 scripts/lockstep.py --spike "$spike_bin" \
    --dut "$build_dir/obj_dir/Vcheckpoint4_top" --elf "$build_dir/smoke.elf" \
    --limit 7 --require-done
if python3 scripts/lockstep.py --spike "$spike_bin" \
    --dut "$build_dir/obj_dir/Vcheckpoint4_top" --elf "$build_dir/smoke.elf" \
    --limit 7 --inject rd@4 > "$build_dir/core-fault.out" 2>&1; then
    echo "CPU lockstep did not detect a wrong load result" >&2
    exit 1
fi
grep -q 'DIVERGENCE at retirement 4' "$build_dir/core-fault.out"
echo 'PASS: real CPU retirement mismatch stopped at event 4'
TRACE_CAPTURE="$build_dir/hang-trace.bin" \
    "$build_dir/obj_dir/Vcheckpoint4_top" --hang-test
python3 scripts/decode_trace.py "$build_dir/hang-trace.bin" \
    > "$build_dir/hang-trace.txt"
grep -q '004 retire priv=3 pc=0x80000010' "$build_dir/hang-trace.txt"
echo 'PASS: captured UART packet decoded to the last retired PC'
"$cross_gcc" -march=rv32ima_zicsr_zifencei -mabi=ilp32 -nostdlib \
    -Wl,--no-relax -T tests/lockstep/smoke.ld tests/core/branch.S \
    -o "$build_dir/branch.elf"
"$cross_objcopy" -O binary "$build_dir/branch.elf" "$build_dir/branch.bin"
export CORE_IMAGE="$build_dir/branch.bin"
python3 scripts/lockstep.py --spike "$spike_bin" \
    --dut "$build_dir/obj_dir/Vcheckpoint4_top" --elf "$build_dir/branch.elf" \
    --limit 8 --require-done
"$cross_gcc" -march=rv32ima_zicsr_zifencei -mabi=ilp32 -nostdlib \
    -Wl,--no-relax -T tests/lockstep/smoke.ld tests/core/loop.S \
    -o "$build_dir/loop.elf"
"$cross_objcopy" -O binary "$build_dir/loop.elf" "$build_dir/loop.bin"
export CORE_IMAGE="$build_dir/loop.bin"
"$build_dir/obj_dir/Vcheckpoint4_top" --ring-test
