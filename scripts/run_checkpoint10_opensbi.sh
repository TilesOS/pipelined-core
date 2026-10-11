#!/usr/bin/env bash
# Requires a PIE-capable RISC-V linker (Debian's riscv64-linux-gnu toolchain).
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo_root"
build_dir="$repo_root/build/privilege"
source_dir=${OPENSBI_SOURCE:-"$repo_root/build/tools/opensbi"}
pinned_commit=a32a91069119e7a5aa31e6bc51d5e00860be3d80 # OpenSBI v1.7
mkdir -p "$build_dir"
if [[ ! -d "$source_dir/.git" ]]; then
    git clone https://github.com/riscv-software-src/opensbi.git "$source_dir"
    git -C "$source_dir" checkout --detach "$pinned_commit"
fi
[[ $(git -C "$source_dir" rev-parse HEAD) == "$pinned_commit" ]] || {
    echo "OpenSBI must be pinned to $pinned_commit" >&2; exit 1;
}
git -C "$source_dir" diff --quiet "$pinned_commit" || {
    echo "OpenSBI tracked sources differ from the pinned revision" >&2; exit 1;
}
export OPENSBI_CC=${OPENSBI_CC:-riscv64-linux-gnu-gcc}
cross_prefix=${OPENSBI_CROSS_COMPILE:-riscv64-linux-gnu-}
linker=${OPENSBI_LD:-"${cross_prefix}ld"}
command -v "$OPENSBI_CC" >/dev/null
command -v "$linker" >/dev/null
# Append -Os after upstream flags; retain upstream's PIE and ABI options.
cat > "$build_dir/opensbi-cc" <<'SHIM'
#!/usr/bin/env bash
exec "$OPENSBI_CC" "$@" -Os
SHIM
chmod +x "$build_dir/opensbi-cc"
cp config/opensbi-checkpoint10.defconfig "$source_dir/platform/generic/configs/checkpoint10_defconfig"
dtc -I dts -O dtb -o "$build_dir/checkpoint10.dtb" config/dts/checkpoint10.dts
make -C "$source_dir" -j"${OPENSBI_BUILD_JOBS:-4}" O="$build_dir/opensbi-gate" \
    PLATFORM=generic PLATFORM_DEFCONFIG=checkpoint10_defconfig CROSS_COMPILE="$cross_prefix" \
    CC="$build_dir/opensbi-cc" LD="$linker" \
    PLATFORM_RISCV_XLEN=32 PLATFORM_RISCV_ISA=rv32ima_zicsr_zifencei \
    FW_JUMP=y FW_JUMP_ADDR=0x80040000 FW_JUMP_FDT_ADDR=0x80060000 \
    FW_FDT_PATH="$build_dir/checkpoint10.dtb" FW_PAYLOAD=n FW_DYNAMIC=n \
    > "$build_dir/opensbi-build.log" 2>&1 || { tail -80 "$build_dir/opensbi-build.log"; exit 1; }
riscv64-unknown-elf-gcc -march=rv32ima_zicsr_zifencei -mabi=ilp32 -nostdlib -Wl,--no-relax \
    -T tests/privilege/opensbi_payload.ld tests/privilege/opensbi_payload.S -o "$build_dir/opensbi_payload.elf"
riscv64-unknown-elf-objcopy -O binary "$build_dir/opensbi_payload.elf" "$build_dir/opensbi_payload.bin"
python3 - "$build_dir" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
firmware = (p / 'opensbi-gate/platform/generic/firmware/fw_jump.bin').read_bytes()
payload = (p / 'opensbi_payload.bin').read_bytes()
assert len(firmware) < 0x40000, 'OpenSBI exceeds 256 KiB allocation'
image = firmware + bytes(0x40000 - len(firmware)) + payload
(p / 'opensbi.hex').write_text(image.hex(' ') + '\n')
print(f'OpenSBI v1.7 firmware: {len(firmware)} bytes (256 KiB cap)')
PY
[[ ${1:-} != --build-only ]] || exit 0
bash scripts/run_checkpoint10.sh --build-only
CACHE_IMAGE="$build_dir/opensbi.hex" "$build_dir/obj/Vprivileged_core_sim" --opensbi
