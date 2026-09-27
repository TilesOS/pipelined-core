#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"
verilator_bin=${VERILATOR_BIN:-verilator}
command -v "$verilator_bin" >/dev/null || { echo "missing tool: $verilator_bin" >&2; exit 1; }
"$verilator_bin" --lint-only --top-module checkpoint8_board_top \
    rtl/bus/axi128_pkg.sv rtl/bus/async_fifo.sv rtl/bus/axi_cdc.sv \
    rtl/bus/axi_fabric.sv rtl/bus/axi_subsystem.sv \
    rtl/top/checkpoint8_core_clock.sv rtl/top/checkpoint8_traffic.sv \
    rtl/top/checkpoint8_uart_report.sv rtl/debug/uart_tx_byte.sv \
    rtl/top/checkpoint8_board_top.sv tests/board/checkpoint8_vendor_stubs.sv
