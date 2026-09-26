# Retirement lockstep simulation

Checkpoint 3 established the simulation interface using a SystemVerilog [`trace_fixture.sv`](../tests/lockstep/trace_fixture.sv) that is deliberately a trace source, **not a CPU**. Checkpoints 4–6 run the actual CPU through the same comparator.

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

The fixture exposes `retire_valid`, `retire_pc`, `retire_insn`, `retire_priv`, `retire_rd`, `retire_rd_data`, `retire_mem_addr`, `retire_mem_rmask`, `retire_mem_wmask`, `retire_mem_wdata`, `retire_trap`, `retire_cause`, and `retire_tval`. The first CPU slice must expose the same simulation-only retirement view. The controller accepts `csr_writes` JSON entries; checkpoint 6 wires the CPU's machine CSR writes to this trace. The JSON `order` counter increments on each architectural event, including a trap boundary. A trap is an event but does not increment `minstret`.

The `--self-test` gate runs one matching fixture trace and injects three independent errors: `rd@4`, `store@3`, and `cause@6`. Each must stop at that event with exit status 1. The CI job runs the same gate on Ubuntu. This fixture-only gate proves the checker and process handshake; the separate CPU slice gate below checks actual RTL.

## First CPU slice

Run `bash scripts/run_core_slice.sh` on the Ubuntu host after the Spike setup. It builds [`rv32_slice.sv`](../rtl/core/rv32_slice.sv) under Verilator and executes two programs in retirement lockstep: the original word load/store and trap smoke program, and a branch program with taken BEQ/JAL, dependent ALU operations, and wrong-path instructions. The same command runs a forced-hang UART dump and a 300-retirement wrap test of the 256-entry trace ring. See the [debug guide](debug.md) for the packet and probe map.

This slice has zero-wait instruction and data ports and implements LUI, ADDI, ADD/SUB, LW, SW, BEQ, JAL, and selected faults in M-mode. It is not yet a complete RV32I core. Checkpoint 5 adds the remaining instructions, hazards, exception behavior, and randomized architectural coverage.

## Complete RV32I gate (checkpoint 5)

Run `bash scripts/run_rv32i.sh` after `bash scripts/run_core_slice.sh`. The latter builds the Verilator CPU executable; the RV32I gate assembles a directed instruction program, four deterministic 400-operation randomized programs, and 15 architectural exception cases. Each program runs to its first trap in retirement lockstep with Spike. The directed program covers the RV32I integer, branch, jump, byte/halfword/word memory, `FENCE`, and x0 behaviors. The exception matrix covers illegal encodings, misalignment, access faults, `ECALL`, and `EBREAK`, with an older store and younger store around the fault to check precise ordering. The CI simulation job runs both gates.

This is project-authored instruction and exception coverage, not the separate RISC-V certification suite.

The comparator derives store width from the instruction, since Spike omits leading zeros when printing store data. A fetch access fault has no Spike instruction trace; its comparison uses faulting PC, cause, and trap value. `--until-trap` stops at the first compared trap and requires the DUT to enter its done state, while `--limit` caps a runaway program.

## M/A, CSR, fence, and contention gate (checkpoint 6)

Run `bash scripts/run_checkpoint6.sh` after `bash scripts/run_core_slice.sh`. It compares directed M/A/CSR programs and self-modifying code with `FENCE.I` against Spike. Four seeded 200-operation M programs stress multiply/divide dependencies, zero divisors, and signed overflow. Ten exception programs cover misaligned and inaccessible atomics plus unsupported encodings and CSR accesses. Counter and reservation contention cases run in the Verilator harness, because clock-cycle counts and an injected competing writer cannot be compared to single-hart Spike instruction by instruction.

The zero-wait memory interface exposes `atomic_lock` while an atomic operation occupies MEM or WB. An external writer must defer while this signal is asserted; after a competing store commits, `external_store_valid` and its address invalidate an overlapping LR reservation. The harness checks same-word and other-word interference, same-hart conflicting stores, and an AMO followed by a deferred competing write.

The fixed Spike invocation models one M-mode hart and a 64 KiB test memory at `0x8000_0000`. This core still halts on a trap rather than entering a handler; checkpoint 10 adds privilege and trap entry. Machine IDs may differ from Spike's implementation-defined values, and cycle counts depend on pipeline stalls, so those values are checked locally. MMIO, DMA, caches, and long Linux execution need matching reference-device behavior or bounded milestones.
