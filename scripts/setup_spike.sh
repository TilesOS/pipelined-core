#!/usr/bin/env bash
set -euo pipefail

# Official Spike v1.1.0; pin the commit because the commit-log format is parsed.
spike_commit=530af85d83781a3dae31a4ace84a573ec255fefa
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source_dir=${SPIKE_SOURCE_DIR:-"$repo_root/build/deps/riscv-isa-sim"}
prefix_dir=${SPIKE_PREFIX_DIR:-"$repo_root/build/tools/spike"}
jobs=${SPIKE_BUILD_JOBS:-4}

for tool in git make g++ dtc; do
    command -v "$tool" >/dev/null || { echo "missing required tool: $tool" >&2; exit 1; }
done
if [[ ! -d "$source_dir/.git" ]]; then
    mkdir -p "$(dirname "$source_dir")"
    git clone --depth 1 --branch v1.1.0 \
        https://github.com/riscv-software-src/riscv-isa-sim.git "$source_dir"
fi
actual_commit=$(git -C "$source_dir" rev-parse HEAD)
if [[ "$actual_commit" != "$spike_commit" ]]; then
    echo "Spike source is $actual_commit; expected $spike_commit" >&2
    exit 1
fi
mkdir -p "$source_dir/build" "$prefix_dir"
cd "$source_dir/build"
# GCC 15 no longer supplies cstdint transitively to this release's fesvr code.
../configure --prefix="$prefix_dir" --enable-commitlog CXXFLAGS="-O2 -include cstdint"
make -j "$jobs"
make install
"$prefix_dir/bin/spike" --help 2>&1 | sed -n '1p'
