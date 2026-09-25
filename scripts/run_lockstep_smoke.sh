#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"
spike_bin=${SPIKE_BIN:-"$repo_root/build/tools/spike/bin/spike"}
cross_gcc=${RISCV_GCC:-riscv64-unknown-elf-gcc}
verilator_bin=${VERILATOR_BIN:-verilator}
build_dir="$repo_root/build/lockstep"

[[ -x "$spike_bin" ]] || { echo "Spike missing: $spike_bin; run scripts/setup_spike.sh" >&2; exit 1; }
command -v "$cross_gcc" >/dev/null || { echo "missing RISC-V cross compiler: $cross_gcc" >&2; exit 1; }
command -v "$verilator_bin" >/dev/null || { echo "missing Verilator: $verilator_bin" >&2; exit 1; }
mkdir -p "$build_dir"
"$cross_gcc" -march=rv32ima_zicsr_zifencei -mabi=ilp32 -nostdlib \
    -Wl,--no-relax -T tests/lockstep/smoke.ld tests/lockstep/smoke.S \
    -o "$build_dir/smoke.elf"
if ! "$verilator_bin" --cc --exe --build --top-module trace_fixture \
    --Mdir "$build_dir/obj_dir" -Wall -Wno-fatal \
    tests/lockstep/trace_fixture.sv tests/lockstep/trace_fixture_main.cpp \
    > "$build_dir/verilator-build.log" 2>&1; then
    echo "Verilator fixture build failed; final log lines:" >&2
    tail -80 "$build_dir/verilator-build.log" >&2
    exit 1
fi
python3 scripts/lockstep.py --spike "$spike_bin" \
    --dut "$build_dir/obj_dir/Vtrace_fixture" --elf "$build_dir/smoke.elf" \
    --limit 7 --require-done

if [[ "${1:-}" == "--self-test" ]]; then
    for fault in rd@4 store@3 cause@6; do
        result_file="$build_dir/fault-${fault//@/-}.out"
        if python3 scripts/lockstep.py --spike "$spike_bin" \
            --dut "$build_dir/obj_dir/Vtrace_fixture" --elf "$build_dir/smoke.elf" \
            --limit 7 --inject "$fault" > "$result_file" 2>&1; then
            echo "fault $fault was not detected" >&2
            exit 1
        fi
        expected=${fault#*@}
        if [[ "$fault" == cause@* ]]; then
            grep -q "DIVERGENCE at trap event $expected" "$result_file"
        else
            grep -q "DIVERGENCE at retirement $expected" "$result_file"
        fi
        echo "PASS: $fault detected at architectural event $expected"
    done
fi
