#!/usr/bin/env bash
# Build a pinned covergroup-capable simulator without changing system tools.
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source_dir="$repo_root/build/tools/verilator-5.052"
commit=ea338be98e1e838d3518809ce8899f85a009963c
if [[ ! -d "$source_dir/.git" ]]; then
    git clone --depth 1 --branch v5.052 https://github.com/verilator/verilator.git "$source_dir"
fi
[[ $(git -C "$source_dir" rev-parse HEAD) == "$commit" ]] || {
    echo 'Unexpected coverage simulator source commit' >&2; exit 1;
}
if [[ ! -x "$source_dir/bin/verilator_bin" ]]; then
    cd "$source_dir"
    autoconf
    ./configure
    make -j "${COVERAGE_BUILD_JOBS:-4}" verilator_bin
fi
"$source_dir/bin/verilator" --version
