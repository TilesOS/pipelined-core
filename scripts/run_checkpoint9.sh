#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"
build_dir="$repo_root/build/cache"
verilator_bin=${VERILATOR_BIN:-verilator}
cross_gcc=${RISCV_GCC:-riscv64-unknown-elf-gcc}
cross_objcopy=${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy}
spike_bin=${SPIKE_BIN:-"$repo_root/build/tools/spike/bin/spike"}
for tool in "$verilator_bin" "$cross_gcc" "$cross_objcopy"; do command -v "$tool" >/dev/null; done
test -x "$spike_bin"
mkdir -p "$build_dir"
sources=(rtl/bus/axi128_pkg.sv rtl/cache/physical_memory_pkg.sv
    rtl/bus/axi_width_bridge.sv rtl/cache/l1_cache.sv)
"$verilator_bin" --binary --timing -Wno-fatal --top-module l1_cache_tb \
    --Mdir "$build_dir/unit_obj" "${sources[@]}" \
    tests/cache/cache_test_memory.sv tests/cache/l1_cache_tb.sv \
    > "$build_dir/unit-build.log" 2>&1 || { tail -80 "$build_dir/unit-build.log"; exit 1; }
"$build_dir/unit_obj/Vl1_cache_tb" +seed=44257
"$build_dir/unit_obj/Vl1_cache_tb" +seed=137
sources+=(rtl/core/rv32_slice.sv rtl/debug/uart_tx_byte.sv rtl/debug/trace_ring_uart.sv
    rtl/top/rv32_cached_core.sv rtl/bus/async_fifo.sv rtl/bus/axi_cdc.sv
    rtl/bus/axi_fabric.sv rtl/bus/axi_subsystem.sv rtl/top/checkpoint9_top.sv)
# Absolute paths also make Verilator's generated Makefile portable.
absolute_sources=()
for source in "${sources[@]}" tests/cache/cache_test_memory.sv tests/cache/cache_test_dma.sv tests/cache/cached_core_sim.sv; do
    absolute_sources+=("$repo_root/$source")
done
"$verilator_bin" --cc --exe --build -Wno-fatal --top-module cached_core_sim \
    --Mdir "$build_dir/core_obj" "${absolute_sources[@]}" \
    "$repo_root/tests/cache/cached_core_main.cpp" \
    > "$build_dir/core-build.log" 2>&1 || { tail -80 "$build_dir/core-build.log"; exit 1; }
for log in "$build_dir/unit-build.log" "$build_dir/core-build.log"; do
    if grep -qE '^%Warning-|^%Error:' "$log"; then cat "$log"; exit 1; fi
done
compile_image() {
    local source=$1 name=$2
    "$cross_gcc" -march=rv32ima_zicsr_zifencei -mabi=ilp32 -nostdlib -Wl,--no-relax \
        -T tests/lockstep/smoke.ld "$source" -o "$build_dir/$name.elf"
    "$cross_objcopy" -O binary "$build_dir/$name.elf" "$build_dir/$name.bin"
    python3 - "$build_dir/$name.bin" "$build_dir/$name.hex" <<'PY'
import pathlib, sys
pathlib.Path(sys.argv[2]).write_text(pathlib.Path(sys.argv[1]).read_bytes().hex(' '))
PY
}
compare_image() {
    local name=$1 limit=${2:-2000}
    CACHE_IMAGE="$build_dir/$name.hex" python3 scripts/lockstep.py \
        --spike "$spike_bin" --dut "$build_dir/core_obj/Vcached_core_sim" \
        --elf "$build_dir/$name.elf" --limit "$limit" --until-trap --watchdog 20000 \
        --memory 0x80000000:0x8000000
}
for test in smoke rv32i_directed m_directed a_directed csr_directed fence_i executable_page uncached_window uncached_executable; do
    case "$test" in
        smoke) source=tests/lockstep/smoke.S ;;
        executable_page|uncached_window|uncached_executable) source="tests/cache/$test.S" ;;
        *) source="tests/core/$test.S" ;;
    esac
    compile_image "$source" "$test"
    compare_image "$test"
done
for ratio in '3 11 137' '11 3 31119'; do
    read -r CORE_HALF MIG_HALF CACHE_SEED <<< "$ratio"
    export CORE_HALF MIG_HALF CACHE_SEED
    compare_image executable_page
    compare_image uncached_window
done
unset CORE_HALF MIG_HALF CACHE_SEED
for seed in 11 29 73 101; do
    python3 tests/core/gen_rv32i.py --seed "$seed" > "$build_dir/random_i_$seed.S"
    compile_image "$build_dir/random_i_$seed.S" "random_i_$seed"
    compare_image "random_i_$seed"
    python3 tests/core/gen_m.py --seed "$seed" > "$build_dir/random_m_$seed.S"
    compile_image "$build_dir/random_m_$seed.S" "random_m_$seed"
    compare_image "random_m_$seed"
done
for test in atomic_contention reservation_store amo_contention burst_reservation fault_load fault_store fault_eviction fault_fence; do
    compile_image "tests/cache/$test.S" "$test"
done
python3 scripts/verify_cached_core.py "$build_dir"
echo 'PASS: checkpoint 9 cached CPU, AXI fabric/CDC and Spike gates'
