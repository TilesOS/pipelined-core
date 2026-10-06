#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo_root"
build_dir="$repo_root/build/privilege"
mkdir -p "$build_dir"
sources=(rtl/bus/axi128_pkg.sv rtl/cache/physical_memory_pkg.sv rtl/bus/axi_width_bridge.sv
    rtl/cache/l1_cache.sv rtl/core/rv32_slice.sv rtl/debug/uart_tx_byte.sv rtl/debug/trace_ring_uart.sv
    rtl/top/rv32_cached_core.sv rtl/bus/async_fifo.sv rtl/bus/axi_cdc.sv rtl/bus/axi_fabric.sv
    rtl/bus/axi_subsystem.sv rtl/top/checkpoint9_top.sv rtl/bus/axi_peripheral_adapter.sv
    rtl/peripherals/clint.sv rtl/peripherals/plic.sv rtl/peripherals/uart16550.sv
    rtl/peripherals/checkpoint10_mmio.sv rtl/top/checkpoint10_top.sv tests/cache/cache_test_memory.sv
    tests/privilege/privileged_core_sim.sv)
absolute_sources=()
for source in "${sources[@]}"; do absolute_sources+=("$repo_root/$source"); done
verilator --cc --exe --build --top-module privileged_core_sim --Mdir "$build_dir/obj" \
    "${absolute_sources[@]}" "$repo_root/tests/privilege/privileged_core_main.cpp" \
    > "$build_dir/build.log" 2>&1 || { tail -80 "$build_dir/build.log"; exit 1; }
[[ ${1:-} != --build-only ]] || exit 0
for test in privilege pmp mmio_faults; do
    riscv64-unknown-elf-gcc -march=rv32ima_zicsr_zifencei -mabi=ilp32 -nostdlib -Wl,--no-relax \
        -T tests/privilege/privilege.ld "tests/privilege/$test.S" -o "$build_dir/$test.elf"
    riscv64-unknown-elf-objcopy -O binary "$build_dir/$test.elf" "$build_dir/$test.bin"
    python3 - "$build_dir/$test" <<'PYIMAGE'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
p.with_suffix('.hex').write_text(p.with_suffix('.bin').read_bytes().hex(' ') + '\n')
PYIMAGE
    for ratio in '5 7 44257' '3 11 137' '11 3 31119'; do
        read -r CORE_HALF MIG_HALF CACHE_SEED <<< "$ratio"
        echo "Running $test with clocks $CORE_HALF/$MIG_HALF, seed $CACHE_SEED"
        CACHE_IMAGE="$build_dir/$test.hex" CORE_HALF="$CORE_HALF" MIG_HALF="$MIG_HALF" CACHE_SEED="$CACHE_SEED" \
            "$build_dir/obj/Vprivileged_core_sim" --run
    done
done
riscv64-unknown-elf-gcc -march=rv32ima_zicsr_zifencei -mabi=ilp32 -nostdlib -Wl,--no-relax \
    -T tests/privilege/privilege.ld tests/cache/fault_fence.S -o "$build_dir/fatal_fence.elf"
riscv64-unknown-elf-objcopy -O binary "$build_dir/fatal_fence.elf" "$build_dir/fatal_fence.bin"
python3 - "$build_dir" <<'PYIMAGE'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
(p / 'fatal_fence.hex').write_text((p / 'fatal_fence.bin').read_bytes().hex(' ') + '\n')
PYIMAGE
CACHE_IMAGE="$build_dir/fatal_fence.hex" FAIL_WRITE_ADDR=80004000 \
    "$build_dir/obj/Vprivileged_core_sim" --fatal-fence
