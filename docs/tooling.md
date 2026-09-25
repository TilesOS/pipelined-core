# Tooling inventory

Checked on 2026-09-24 and updated on 2026-09-25. This is an observation log, not a list of prerequisites assumed to be installed.

| Host | Observed state |
|---|---|
| Mac | macOS 27.0 on arm64; Apple Git 2.54.0, Python 3, Homebrew 6.0.13, GitHub CLI 2.101.0, ripgrep 15.2.0, and OrbStack commands are present. Git author configuration is set to `TilesOS`. Verilator, Icarus Verilog, Yosys, RISC-V GCC, QEMU RISC-V, and Vivado were not found on the current PATH. |
| OrbStack `ece-dev` | Ubuntu 26.04 LTS, arm64. Git 2.53.0, Verilator 5.032, Python 3, and CMake 4.2.3 are present. Icarus Verilog, Yosys, Vivado, RISC-V GCC, QEMU RISC-V, and Ninja were not found on the current PATH. The machine was started for inventory. |
| OrbStack `chipyard-x86` | Ubuntu 26.04 LTS, x86-64. Git 2.53.0 and Python 3.14.4 are present. Verilator, Icarus Verilog, Yosys, Vivado, RISC-V GCC, QEMU RISC-V, CMake, and Ninja were not found on the current PATH. The machine was started for inventory. |
| Ubuntu PC | The owner confirms `x86_64` architecture and Vivado 2026.1. This is user-reported because the PC is not connected to this workspace. License status and board cable access remain unverified. |
| GitHub | Public repository [TilesOS/pipelined-core](https://github.com/TilesOS/pipelined-core) is created on `main`; the first repository check succeeded. GitHub CLI is installed. The connected GitHub app published the initial files to this repository. |

Run the following on each development host when available and add its results to the checkpoint record:

```sh
uname -s -m
git --version
python3 --version
verilator --version
vivado -version
command -v riscv32-unknown-elf-gcc
command -v riscv64-unknown-linux-gnu-gcc
command -v qemu-system-riscv32
```

Run the version and license checks directly on the Ubuntu PC before FPGA synthesis or programming. Generated Vivado IP and bitstreams remain build outputs; the repository will track source Tcl and constraints as those checkpoints are implemented.
