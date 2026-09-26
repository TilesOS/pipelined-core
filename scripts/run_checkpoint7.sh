#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"
build_dir="$repo_root/build/bus"
verilator_bin=${VERILATOR_BIN:-verilator}
command -v "$verilator_bin" >/dev/null || { echo "missing tool: $verilator_bin" >&2; exit 1; }
"$verilator_bin" --version
mkdir -p "$build_dir"

"$verilator_bin" --binary --timing -Wno-fatal --top-module axi_bus_tb \
    --Mdir "$build_dir/obj_dir" \
    rtl/bus/axi128_pkg.sv rtl/bus/async_fifo.sv rtl/bus/axi_cdc.sv \
    rtl/bus/axi_fabric.sv rtl/bus/axi_subsystem.sv \
    tests/bus/axi_test_slave.sv tests/bus/axi_bus_tb.sv \
    > "$build_dir/bus-build.log" 2>&1 || {
        tail -80 "$build_dir/bus-build.log" >&2; exit 1;
    }
"$verilator_bin" --binary --timing -Wno-fatal --top-module axi_bridge_tb \
    --Mdir "$build_dir/bridge_obj" \
    rtl/bus/axi128_pkg.sv rtl/bus/axi_width_bridge.sv \
    tests/bus/axi_test_slave.sv tests/bus/axi_bridge_tb.sv \
    > "$build_dir/bridge-build.log" 2>&1 || {
        tail -80 "$build_dir/bridge-build.log" >&2; exit 1;
    }
"$verilator_bin" --binary --timing -Wno-fatal --top-module axi_peripheral_tb \
    --Mdir "$build_dir/peripheral_obj" \
    rtl/bus/axi128_pkg.sv rtl/bus/axi_width_bridge.sv \
    rtl/bus/axi_peripheral_adapter.sv tests/bus/axi_peripheral_tb.sv \
    > "$build_dir/peripheral-build.log" 2>&1 || {
        tail -80 "$build_dir/peripheral-build.log" >&2; exit 1;
    }

"$build_dir/bridge_obj/Vaxi_bridge_tb"
"$build_dir/peripheral_obj/Vaxi_peripheral_tb"
"$build_dir/obj_dir/Vaxi_bus_tb" +core_half=5 +mig_half=7 +seed=44257 +reset_beats=1
"$build_dir/obj_dir/Vaxi_bus_tb" +core_half=3 +mig_half=11 +seed=137 +reset_beats=7
"$build_dir/obj_dir/Vaxi_bus_tb" +core_half=11 +mig_half=3 +seed=31119 +reset_beats=15
"$build_dir/obj_dir/Vaxi_bus_tb" +core_half=4 +mig_half=13 +seed=7641 +reset_beats=4
"$build_dir/obj_dir/Vaxi_bus_tb" +core_half=13 +mig_half=4 +seed=59129 +reset_beats=11

if grep -qE '^%Warning-|^%Error:' "$build_dir/bus-build.log" \
    "$build_dir/bridge-build.log" "$build_dir/peripheral-build.log"; then
    echo "Verilator emitted warnings or errors:" >&2
    grep -E '^%Warning-|^%Error:' "$build_dir/bus-build.log" \
        "$build_dir/bridge-build.log" "$build_dir/peripheral-build.log" >&2
    exit 1
fi
