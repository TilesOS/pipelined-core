# Retirement lockstep simulation

Checkpoint 3 establishes the simulation interface before CPU RTL exists. The SystemVerilog [`trace_fixture.sv`](../tests/lockstep/trace_fixture.sv) is deliberately a trace source, **not a CPU**. It represents the six instructions and illegal-instruction trap in [`smoke.S`](../tests/lockstep/smoke.S). Checkpoint 4 replaces this fixture with the first CPU slice.

## Ubuntu setup and smoke gate

On an Ubuntu development host, install Verilator, a RISC-V bare-metal cross compiler, a C++ build toolchain, `dtc`, and Boost headers/regex. The validated OrbStack command was:

```sh
sudo apt-get install -y verilator gcc-riscv64-unknown-elf \
  device-tree-compiler libboost-dev libboost-regex-dev autoconf automake libtool
bash scripts/setup_spike.sh
bash scripts/run_lockstep_smoke.sh --self-test
```

`setup_spike.sh` checks out official [Spike v1.1.0](https://github.com/riscv-software-src/riscv-isa-sim/releases/tag/v1.1.0) at `530af85d83781a3dae31a4ace84a573ec255fefa`, builds it with `--enable-commitlog`, and installs it under ignored `build/tools/spike`. The explicit `cstdint` include works around a GCC 15 build error in this release. The setup script verifies the source commit before building. `run_lockstep_smoke.sh` creates the ELF and Verilator executable under ignored `build/lockstep`.

Ubuntu 24.04's Boost packaging also needs `libboost-system-dev` for Spike's Asio link check; the CI job installs it. Ubuntu 26.04's Boost 1.90 package used in OrbStack provides the needed support without a separate package.

## Protocol

The Python [lockstep controller](../scripts/lockstep.py) sends `step` to the Verilator process and waits for one JSON event. A `cycle` response advances no reference instruction; after a `retire` event, the controller sends exactly one `run 1` to Spike's interactive debugger through a PTY. It compares the events before permitting another DUT cycle. A watchdog stops a DUT that never retires. Spike's five internal boot-ROM instructions are skipped by querying its PC until it equals the ELF entry; they are not counted as DUT retirements.

For each ordinary retirement, the comparison checks PC, instruction word, privilege mode, GPR write index/value, CSR writes (when provided), load byte addresses, and store byte values/addresses. For a trap it checks faulting PC, instruction, cause, and trap value. The DUT trace uses the instruction's effective memory address, byte-lane read/write masks, and aligned write data; the controller normalizes those into byte-addressed effects before comparison. Spike v1.1.0's commit log does not print load data, so a load's destination-register value and read addresses establish its observed result. The controller reconstructs known DUT GPR, CSR, and memory state; on divergence it queries all 32 Spike GPRs and selected trap/MMU CSRs, then prints the first mismatch and the previous eight events.

The fixture exposes `retire_valid`, `retire_pc`, `retire_insn`, `retire_priv`, `retire_rd`, `retire_rd_data`, `retire_mem_addr`, `retire_mem_rmask`, `retire_mem_wmask`, `retire_mem_wdata`, `retire_trap`, `retire_cause`, and `retire_tval`. The first CPU slice must expose the same simulation-only retirement view. The controller accepts optional `csr_writes` JSON entries; checkpoint 6 adds the CPU's CSR trace wiring. The JSON `order` counter increments on each architectural event, including a trap boundary. A trap is an event but does not increment `minstret`.

The `--self-test` gate runs one matching trace and injects three independent errors: `rd@4`, `store@3`, and `cause@6`. Each must stop at that event with exit status 1. The CI job runs the same gate on Ubuntu. This proves the checker and process handshake; it does not prove CPU instruction correctness because no CPU RTL exists yet.

## Future coverage

The fixed Spike invocation currently models one M-mode hart and a 64 KiB test memory at `0x8000_0000`. Checkpoints 5–6 add randomized RV32I and M/A/CSR programs; checkpoints 10–11 align device and privilege behavior for interrupts and Sv32. MMIO, DMA, caches, and long Linux execution need matching reference-device behavior or bounded milestones. The first core integration must test stalls, branch flushes, trap ordering, and store visibility through the same retirement interface.
