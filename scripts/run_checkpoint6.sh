#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"
build_dir="$repo_root/build/core"
spike_bin=${SPIKE_BIN:-"$repo_root/build/tools/spike/bin/spike"}
cross_gcc=${RISCV_GCC:-riscv64-unknown-elf-gcc}
cross_objcopy=${RISCV_OBJCOPY:-riscv64-unknown-elf-objcopy}
for program in m_directed a_directed csr_directed fence_i; do
    "$cross_gcc" -march=rv32ima_zicsr_zifencei -mabi=ilp32 -nostdlib -Wl,--no-relax \
        -T tests/lockstep/smoke.ld "tests/core/${program}.S" -o "$build_dir/${program}.elf"
    "$cross_objcopy" -O binary "$build_dir/${program}.elf" "$build_dir/${program}.bin"
    CORE_IMAGE="$build_dir/${program}.bin" python3 scripts/lockstep.py \
        --spike "$spike_bin" --dut "$build_dir/obj_dir/Vcheckpoint4_top" \
        --elf "$build_dir/${program}.elf" --limit 80 --until-trap
done
for program in atomic_contention reservation_store; do
    "$cross_gcc" -march=rv32ima_zicsr_zifencei -mabi=ilp32 -nostdlib -Wl,--no-relax \
        -T tests/lockstep/smoke.ld "tests/core/${program}.S" -o "$build_dir/${program}.elf"
    "$cross_objcopy" -O binary "$build_dir/${program}.elf" "$build_dir/${program}.bin"
done
CORE_IMAGE="$build_dir/atomic_contention.bin" \
    "$build_dir/obj_dir/Vcheckpoint4_top" --contention-test
CORE_IMAGE="$build_dir/reservation_store.bin" \
    "$build_dir/obj_dir/Vcheckpoint4_top" --self-store-test
"$cross_gcc" -march=rv32ima_zicsr_zifencei -mabi=ilp32 -nostdlib -Wl,--no-relax \
    -T tests/lockstep/smoke.ld tests/core/amo_contention.S -o "$build_dir/amo_contention.elf"
"$cross_objcopy" -O binary "$build_dir/amo_contention.elf" "$build_dir/amo_contention.bin"
CORE_IMAGE="$build_dir/amo_contention.bin" \
    "$build_dir/obj_dir/Vcheckpoint4_top" --amo-contention-test
"$cross_gcc" -march=rv32ima_zicsr_zifencei -mabi=ilp32 -nostdlib -Wl,--no-relax \
    -T tests/lockstep/smoke.ld tests/core/csr_counters.S -o "$build_dir/csr_counters.elf"
"$cross_objcopy" -O binary "$build_dir/csr_counters.elf" "$build_dir/csr_counters.bin"
CORE_IMAGE="$build_dir/csr_counters.bin" \
    "$build_dir/obj_dir/Vcheckpoint4_top" --counter-test
for seed in 5 6 7 8; do
    python3 tests/core/gen_m.py --seed "$seed" > "$build_dir/random_m_${seed}.S"
    "$cross_gcc" -march=rv32ima_zicsr_zifencei -mabi=ilp32 -nostdlib -Wl,--no-relax \
        -T tests/lockstep/smoke.ld "$build_dir/random_m_${seed}.S" \
        -o "$build_dir/random_m_${seed}.elf"
    "$cross_objcopy" -O binary "$build_dir/random_m_${seed}.elf" \
        "$build_dir/random_m_${seed}.bin"
    CORE_IMAGE="$build_dir/random_m_${seed}.bin" python3 scripts/lockstep.py \
        --spike "$spike_bin" --dut "$build_dir/obj_dir/Vcheckpoint4_top" \
        --elf "$build_dir/random_m_${seed}.elf" --limit 260 --until-trap
    echo "PASS: randomized M seed $seed"
done
for test_case in lr_misaligned sc_misaligned amo_misaligned lr_access sc_access \
                 amo_access invalid_lr invalid_amo invalid_csr readonly_csr; do
    case "$test_case" in
        lr_misaligned) fault='lr.w x3, (x4)' ;;
        sc_misaligned) fault='sc.w x3, x2, (x4)' ;;
        amo_misaligned) fault='amoadd.w x3, x2, (x4)' ;;
        lr_access) fault='lr.w x3, (x5)' ;;
        sc_access) fault='sc.w x3, x2, (x5)' ;;
        amo_access) fault='amoadd.w x3, x2, (x5)' ;;
        invalid_lr) fault='.word 0x1010a1af' ;; # LR.W with nonzero rs2
        invalid_amo) fault='.word 0x0020b1af' ;; # RV32A doubleword width
        invalid_csr) fault='csrr x3, 0x7ff' ;;
        readonly_csr) fault='csrw mhartid, x2' ;;
    esac
    cat > "$build_dir/checkpoint6_${test_case}.S" <<PROGRAM
.option norvc
.section .text
.globl _start
_start:
    lui x1, 0x80001
    addi x2, x0, 5
    sw x2, 0(x1)
    addi x4, x1, 2
    lui x5, 0x80010
    $fault
    sw x2, 4(x1)
PROGRAM
    "$cross_gcc" -march=rv32ima_zicsr_zifencei -mabi=ilp32 -nostdlib -Wl,--no-relax \
        -T tests/lockstep/smoke.ld "$build_dir/checkpoint6_${test_case}.S" \
        -o "$build_dir/checkpoint6_${test_case}.elf"
    "$cross_objcopy" -O binary "$build_dir/checkpoint6_${test_case}.elf" \
        "$build_dir/checkpoint6_${test_case}.bin"
    CORE_IMAGE="$build_dir/checkpoint6_${test_case}.bin" python3 scripts/lockstep.py \
        --spike "$spike_bin" --dut "$build_dir/obj_dir/Vcheckpoint4_top" \
        --elf "$build_dir/checkpoint6_${test_case}.elf" --limit 9 --until-trap
    echo "PASS: $test_case precise trap"
done
