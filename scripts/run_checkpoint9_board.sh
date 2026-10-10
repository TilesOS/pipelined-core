#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"
build_dir="$repo_root/build/checkpoint9-board"
verilator_bin=${VERILATOR_BIN:-verilator}
bash scripts/build_checkpoint9_rom.sh
sources=(rtl/bus/axi128_pkg.sv rtl/cache/physical_memory_pkg.sv
    rtl/bus/async_fifo.sv rtl/bus/axi_cdc.sv rtl/bus/axi_fabric.sv rtl/bus/axi_subsystem.sv
    rtl/bus/axi_width_bridge.sv rtl/bus/axi_peripheral_adapter.sv rtl/cache/l1_cache.sv
    rtl/core/rv32_slice.sv rtl/debug/uart_tx_byte.sv rtl/debug/trace_ring_uart.sv
    rtl/top/rv32_cached_core.sv rtl/top/checkpoint9_top.sv
    rtl/top/checkpoint9_smoke_mmio.sv rtl/top/checkpoint9_smoke_dma.sv
    rtl/top/checkpoint9_uart_report.sv rtl/top/checkpoint9_board_system.sv)
"$verilator_bin" --binary --timing -Wno-fatal --top-module checkpoint9_board_tb \
    --Mdir "$build_dir/board_obj" "${sources[@]}" \
    tests/cache/cache_test_memory.sv tests/board/checkpoint9_board_tb.sv \
    > "$build_dir/board-build.log" 2>&1 || { tail -80 "$build_dir/board-build.log"; exit 1; }
"$verilator_bin" --lint-only --top-module checkpoint9_board_top "${sources[@]}" \
    rtl/top/checkpoint8_core_clock.sv rtl/top/checkpoint9_board_top.sv \
    tests/board/checkpoint8_vendor_stubs.sv \
    > "$build_dir/board-lint.log" 2>&1 || { cat "$build_dir/board-lint.log"; exit 1; }
if grep -qE '^%Warning-|^%Error:' "$build_dir/board-build.log" "$build_dir/board-lint.log"; then
    grep -E '^%Warning-|^%Error:' "$build_dir/board-build.log" "$build_dir/board-lint.log"
    exit 1
fi
"$build_dir/board_obj/Vcheckpoint9_board_tb" +core_half=10 +mig_half=6 +seed=44257 \
    +capture="$build_dir/sim-uart.dat"
python3 scripts/decode_checkpoint9.py "$build_dir/sim-uart.dat"
"$build_dir/board_obj/Vcheckpoint9_board_tb" +core_half=7 +mig_half=11 +seed=137
"$build_dir/board_obj/Vcheckpoint9_board_tb" +seed=137 +fail_write_addr=87ff8000 \
    +expect_failure +capture="$build_dir/sim-failed-uart.dat"
if python3 scripts/decode_checkpoint9.py "$build_dir/sim-failed-uart.dat"; then
    echo 'ERROR: decoder accepted the injected DMA failure' >&2; exit 1
else
    status=$?
    test "$status" -eq 2
fi
