# Checkpoint 3: Verilator and Spike lockstep

Status: complete on 2026-09-25 for the simulation infrastructure. The [simulation guide](../simulation.md) specifies the interface and commands. No CPU RTL exists yet; the SystemVerilog source used here is an explicit trace fixture.

## Delivered

- A reproducible Spike v1.1.0 source build, pinned to commit `530af85d83781a3dae31a4ace84a573ec255fefa` with commit logging enabled.
- A Verilator-built SystemVerilog fixture and RV32IMA_Zicsr_Zifencei ELF with six ordinary instructions, a word store/load, and an illegal-instruction trap.
- A controller that steps the DUT and Spike together, compares architectural and memory effects immediately, and stops before the DUT's next cycle on any divergence.
- A mutation gate for wrong register data, wrong store data, and wrong trap cause. The failed Spike build without `--enable-commitlog` and the command-file stepping timeout both have small reproducers; the final setup enables commit logging and uses a PTY.
- The first Ubuntu GitHub Actions run failed at Spike's Boost::Asio configure check because the runner needed `libboost-system-dev`. The CI dependency list now includes it; this is a host packaging issue, not a comparator mismatch.
- The next clean runner exposed an older Verilator path rule: it resolved the C++ fixture path from the generated object directory. The runner now receives absolute fixture paths, and build failures print the Verilator log. The same command passed again on `ece-dev` after this fix.

## Observed evidence on OrbStack `ece-dev`

```text
Verilator 5.032 2025-01-01 rev (Debian 5.032-1)
riscv64-unknown-elf-gcc (14.2.0+19) 14.2.0
Spike RISC-V ISA Simulator 1.1.0
Spike aligned at 0x80000000 after 5 startup instructions
PASS: 7 architectural events (6 retirements, 1 trap) match Spike, including register and memory effects
PASS: rd@4 detected at architectural event 4
PASS: store@3 detected at architectural event 3
PASS: cause@6 detected at architectural event 6
```

`bash scripts/run_lockstep_smoke.sh --self-test` exited 0. Verilator emitted no warnings in `build/lockstep/verilator-build.log`. The injected store mismatch reported the differing bytes at `0x80001000`, the prior three events, 32 Spike GPRs, and known DUT state. Source parsing and `git diff --check` also passed locally.

[GitHub Actions run #15](https://github.com/TilesOS/pipelined-core/actions/runs/36170726046) passed both `docs` and `lockstep` on a clean Ubuntu runner. The lockstep job printed the same seven-event match and all three expected first-divergence detections.

## Scope of proof

This proves the simulation and first-divergence machinery against a known trace, including a trap. It does **not** establish that a CPU exists, passes RV32I, or boots firmware. Checkpoint 4 integrates the first real pipeline retirement port, trace ring, UART dump, and ILA probes. Later checkpoints expand the reference environment for CSRs, interrupts, translation, and MMIO.
