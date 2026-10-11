#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo_root"
board_dir="$repo_root/build/checkpoint10-board"
python3 tests/board/checkpoint10_image_test.py
bash scripts/build_checkpoint10_board_image.sh
for unit in loader loader_compact uart_owner; do
    block=${unit%_compact}
    unit_flags=()
    if [[ $unit == loader_compact ]]; then unit_flags=(-GCOMPACT=1); fi
    unit_sources=("rtl/top/checkpoint10_image_loader.sv" tests/cache/cache_test_memory.sv)
    if [[ $block == uart_owner ]]; then unit_sources=(rtl/debug/checkpoint10_uart_owner.sv); fi
    verilator --binary --timing --top-module "checkpoint10_${block}_tb" \
        --Mdir "$board_dir/${unit}_obj" "${unit_flags[@]}" rtl/bus/axi128_pkg.sv "${unit_sources[@]}" \
        "tests/board/checkpoint10_${block}_tb.sv" > "$board_dir/$unit-build.log" 2>&1 || {
            tail -80 "$board_dir/$unit-build.log"; exit 1;
        }
    "$board_dir/${unit}_obj/Vcheckpoint10_${block}_tb"
done
mapfile -t sources < scripts/checkpoint10_sources.txt
verilator --lint-only -I"$board_dir" --top-module checkpoint10_board_top \
    "${sources[@]}" tests/board/checkpoint8_vendor_stubs.sv
verilator --cc --exe --build -I"$board_dir" --top-module checkpoint10_board_sim \
    --Mdir "$board_dir/obj" "${sources[@]}" tests/cache/cache_test_memory.sv \
    tests/board/checkpoint10_board_sim.sv "$repo_root/tests/board/checkpoint10_board_main.cpp" \
    > "$board_dir/build.log" 2>&1 || { tail -80 "$board_dir/build.log"; exit 1; }
for ratio in '5 7' '3 11'; do
    read -r CORE_HALF MIG_HALF <<< "$ratio"
    echo "Board integration simulation: core/MIG half-periods $CORE_HALF/$MIG_HALF"
    CORE_HALF="$CORE_HALF" MIG_HALF="$MIG_HALF" "$board_dir/obj/Vcheckpoint10_board_sim"
done
