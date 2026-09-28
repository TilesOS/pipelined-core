#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"
build_dir="$repo_root/build/checkpoint8"
verilator_bin=${VERILATOR_BIN:-verilator}
command -v "$verilator_bin" >/dev/null || { echo "missing tool: $verilator_bin" >&2; exit 1; }
mkdir -p "$build_dir"
"$verilator_bin" --binary --timing -Wno-fatal --top-module checkpoint8_traffic_tb \
    --Mdir "$build_dir/traffic_obj" \
    rtl/bus/axi128_pkg.sv rtl/bus/async_fifo.sv rtl/bus/axi_cdc.sv \
    rtl/bus/axi_fabric.sv rtl/bus/axi_subsystem.sv \
    rtl/top/checkpoint8_traffic.sv rtl/top/checkpoint8_uart_report.sv \
    rtl/debug/uart_tx_byte.sv tests/bus/axi_test_slave.sv \
    tests/board/checkpoint8_traffic_tb.sv \
    > "$build_dir/traffic-build.log" 2>&1 || {
        tail -80 "$build_dir/traffic-build.log" >&2; exit 1;
    }
if grep -qE '^%Warning-|^%Error:' "$build_dir/traffic-build.log"; then
    grep -E '^%Warning-|^%Error:' "$build_dir/traffic-build.log" >&2
    exit 1
fi
"$build_dir/traffic_obj/Vcheckpoint8_traffic_tb" +core_half=10 +mig_half=6 +seed=44257
"$build_dir/traffic_obj/Vcheckpoint8_traffic_tb" +core_half=7 +mig_half=11 +seed=137
