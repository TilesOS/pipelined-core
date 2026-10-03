#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"
build_dir="$repo_root/build/coverage"
mkdir -p "$build_dir"
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
python3 scripts/report_cpu_coverage.py "$raw_dir" \
    --json "$build_dir/summary.json" --min-percent "${CPU_COVERAGE_MIN_PERCENT:-90}" \
    | tee "$build_dir/summary.txt"
echo "Raw functional coverage: $raw_dir"
