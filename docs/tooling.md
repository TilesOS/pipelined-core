# Tooling inventory

Checked on 2026-09-24. This is an observation log, not a list of prerequisites assumed to be installed.

| Host | Observed state |
|---|---|
| Mac | macOS 27.0 on arm64; Apple Command Line Tools Git, Python 3, Homebrew 6.0.13, and OrbStack commands are present. Git author configuration is set to `TilesOS`. `gh`, Verilator, Icarus Verilog, Yosys, RISC-V GCC, QEMU RISC-V, and Vivado were not found on the current PATH. |
| OrbStack | The UI shows stopped Ubuntu `ece-dev` (arm64) and `chipyard-x86` (amd64) machines. `orbctl list` timed out, so software installed inside them has not been inventoried. |
| Ubuntu PC | The owner reports an x86-64 Ubuntu PC with Vivado installed. It is not connected to this workspace, so its Vivado version, license, and board cable access remain to be verified there. |
| GitHub | Connected account reports login `TilesOS`. The requested `TilesOS/pipelined-core` repository did not exist at the start of checkpoint 1. |

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

The Ubuntu PC must be checked before any FPGA synthesis or programming checkpoint. Generated Vivado IP and bitstreams remain build outputs; the repository will track source Tcl and constraints as those checkpoints are implemented.
