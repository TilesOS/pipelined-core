#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo_root"
build_dir="$repo_root/build/peripherals"
verilator_bin=verilator
command -v "$verilator_bin" >/dev/null || { echo "missing tool: $verilator_bin" >&2; exit 1; }
mkdir -p "$build_dir"
for block in clint plic uart16550; do
    "$verilator_bin" --binary --timing -Wno-fatal --top-module "$block"_tb \
        --Mdir "$build_dir/"$block"_obj" \
        "rtl/peripherals/$block.sv" "tests/peripherals/"$block"_tb.sv" \
        > "$build_dir/$block-build.log" 2>&1 || {
            tail -80 "$build_dir/$block-build.log" >&2; exit 1;
        }
    if grep -qE '^%Warning-|^%Error:' "$build_dir/$block-build.log"; then
        grep -E '^%Warning-|^%Error:' "$build_dir/$block-build.log" >&2
        exit 1
    fi
    "$build_dir/"$block"_obj/V"$block"_tb"
done
verilator --binary --timing --top-module checkpoint10_mmio_tb \
    --Mdir "$build_dir/mmio_obj" rtl/bus/axi128_pkg.sv rtl/bus/axi_peripheral_adapter.sv \
    rtl/peripherals/{clint,plic,uart16550,checkpoint10_mmio}.sv tests/peripherals/checkpoint10_mmio_tb.sv \
    > "$build_dir/mmio-build.log" 2>&1 || { tail -80 "$build_dir/mmio-build.log"; exit 1; }
"$build_dir/mmio_obj/Vcheckpoint10_mmio_tb"
