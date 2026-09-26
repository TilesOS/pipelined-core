#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"
build_dir="$repo_root/build/core"
spike_bin=${SPIKE_BIN:-"$repo_root/build/tools/spike/bin/spike"}
cross_gcc=${RISCV_GCC:-riscv64-unknown-elf-gcc}
cross_objcopy=${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy}
"$cross_gcc" -march=rv32i -mabi=ilp32 -nostdlib -Wl,--no-relax \
    -T tests/lockstep/smoke.ld tests/core/rv32i_directed.S \
    -o "$build_dir/rv32i_directed.elf"
"$cross_objcopy" -O binary "$build_dir/rv32i_directed.elf" "$build_dir/rv32i_directed.bin"
CORE_IMAGE="$build_dir/rv32i_directed.bin" python3 scripts/lockstep.py \
    --spike "$spike_bin" --dut "$build_dir/obj_dir/Vcheckpoint4_top" \
    --elf "$build_dir/rv32i_directed.elf" --limit 100 --until-trap
for seed in 1 2 3 4; do
    python3 tests/core/gen_rv32i.py --seed "$seed" --count 400 > "$build_dir/random_${seed}.S"
    "$cross_gcc" -march=rv32i -mabi=ilp32 -nostdlib -Wl,--no-relax \
        -T tests/lockstep/smoke.ld "$build_dir/random_${seed}.S" \
        -o "$build_dir/random_${seed}.elf"
    "$cross_objcopy" -O binary "$build_dir/random_${seed}.elf" "$build_dir/random_${seed}.bin"
    CORE_IMAGE="$build_dir/random_${seed}.bin" python3 scripts/lockstep.py \
        --spike "$spike_bin" --dut "$build_dir/obj_dir/Vcheckpoint4_top" \
        --elf "$build_dir/random_${seed}.elf" --limit 450 --until-trap
    echo "PASS: randomized seed $seed"
done
for test_case in illegal invalid_shift invalid_op invalid_store lh_misaligned lw_misaligned \
                 sh_misaligned sw_misaligned branch_misaligned jalr_misaligned \
                 instruction_access load_access store_access ecall ebreak; do
    case "$test_case" in
        illegal) fault='.word 0xffffffff' ;;
        invalid_shift) fault='.word 0x40001093' ;; # SLLI with forbidden funct7
        invalid_op) fault='.word 0x400020b3' ;; # SLT with forbidden funct7
        invalid_store) fault='.word 0x0020b023' ;; # reserved store width
        lh_misaligned) fault='lh x3, 1(x1)' ;;
        lw_misaligned) fault='lw x3, 2(x1)' ;;
        sh_misaligned) fault='sh x2, 1(x1)' ;;
        sw_misaligned) fault='sw x2, 2(x1)' ;;
        branch_misaligned) fault='.word 0x00000163' ;; # BEQ x0,x0,+2
        jalr_misaligned) fault='jalr x0, 2(x1)' ;;
        instruction_access) fault=$'lui x3, 0x80010\n    jalr x0, 0(x3)' ;;
        load_access) fault=$'lui x3, 0x80010\n    lw x4, 0(x3)' ;;
        store_access) fault=$'lui x3, 0x80010\n    sw x2, 0(x3)' ;;
        ecall) fault='ecall' ;;
        ebreak) fault='ebreak' ;;
    esac
    cat > "$build_dir/exception_${test_case}.S" <<PROGRAM
.option norvc
.section .text
.globl _start
_start:
    lui x1, 0x80001
    addi x2, x0, 0x12
    sw x2, 0(x1)
    $fault
    sw x2, 4(x1)
PROGRAM
    "$cross_gcc" -march=rv32i -mabi=ilp32 -nostdlib -Wl,--no-relax \
        -T tests/lockstep/smoke.ld "$build_dir/exception_${test_case}.S" \
        -o "$build_dir/exception_${test_case}.elf"
    "$cross_objcopy" -O binary "$build_dir/exception_${test_case}.elf" \
        "$build_dir/exception_${test_case}.bin"
    CORE_IMAGE="$build_dir/exception_${test_case}.bin" python3 scripts/lockstep.py \
        --spike "$spike_bin" --dut "$build_dir/obj_dir/Vcheckpoint4_top" \
        --elf "$build_dir/exception_${test_case}.elf" --limit 6 --until-trap
    echo "PASS: precise $test_case trap"
done
