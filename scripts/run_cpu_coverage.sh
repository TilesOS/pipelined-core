#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"
build_dir="$repo_root/build/coverage"
mkdir -p "$build_dir"
rm -f "$build_dir/summary.json" "$build_dir/summary.txt"
# A fresh directory prevents stale coverage from an earlier regression.
raw_dir=$(mktemp -d "$build_dir/run-XXXXXX")
export CPU_COVERAGE_DIR="$raw_dir" CPU_FUNCTIONAL_COVERAGE=1
if [[ -z ${VERILATOR_BIN:-} ]]; then
    bash scripts/setup_coverage_verilator.sh > "$build_dir/tool-setup.log" 2>&1 || {
        tail -40 "$build_dir/tool-setup.log" >&2; exit 1;
    }
    export VERILATOR_BIN="$repo_root/build/tools/verilator-5.052/bin/verilator"
fi
bash scripts/run_core_slice.sh
bash scripts/run_rv32i.sh
bash scripts/run_checkpoint6.sh
cross_gcc=${RISCV_GCC:-riscv64-unknown-elf-gcc}
cross_objcopy=${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy}
for program in coverage_directed coverage_ids; do
    "$cross_gcc" -march=rv32ima_zicsr_zifencei -mabi=ilp32 -nostdlib -Wl,--no-relax \
        -T tests/lockstep/smoke.ld "tests/core/$program.S" -o "build/core/$program.elf"
    "$cross_objcopy" -O binary "build/core/$program.elf" "build/core/$program.bin"
done
CORE_IMAGE="$repo_root/build/core/coverage_directed.bin" python3 scripts/lockstep.py \
    --spike "${SPIKE_BIN:-$repo_root/build/tools/spike/bin/spike}" \
    --dut "$repo_root/build/core/obj_dir/Vcheckpoint4_top" \
    --elf "$repo_root/build/core/coverage_directed.elf" --limit 30 --until-trap
CORE_IMAGE="$repo_root/build/core/coverage_ids.bin" \
    "$repo_root/build/core/obj_dir/Vcheckpoint4_top" --coverage-ids-test
if [[ ${CPU_CROSS_CLOSE:-1} == 1 ]]; then
    python3 scripts/close_cpu_cross_coverage.py "$raw_dir" \
        --baseline "$build_dir/baseline.json" --output "$build_dir/seed-replay.json" \
        --replay tests/core/hazard_seeds.json
fi
python3 scripts/check_cpu_coverage.py
python3 scripts/report_cpu_coverage.py "$raw_dir" \
    --json "$build_dir/summary.json" --min-percent "${CPU_COVERAGE_MIN_PERCENT:-100}" \
    | tee "$build_dir/summary.txt"
echo "Raw functional coverage: $raw_dir"
