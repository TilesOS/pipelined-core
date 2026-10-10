# Pipelined Core

A checkpoint-driven project to build a custom Linux-capable RV32IMA CPU, L1 caches, AXI interconnect, and INT8 matrix DMA accelerator for the Nexys A7-100T.

The [project plan](docs/project-plan.md) defines the architecture, 18 checkpoints, acceptance gates, and current progress. Start there before implementing a new subsystem.

## Current state

Checkpoints 1–7 are complete in simulation, and [checkpoint 8 DDR2 board bring-up](docs/checkpoints/08-ddr-bringup.md) is complete on the Nexys A7-100T. [Checkpoint 9](docs/checkpoints/09-caches.md) connects the RV32IMA CPU to separate 8 KiB, two-way caches and the AXI fabric/clock crossing. Physical addresses select cached DDR or uncached ROM/MMIO/DMA accesses. Dirty eviction, full `FENCE.I`, executable-page changes, uncached atomics, competing DMA writes, and precise bus faults pass RTL tests and Spike lockstep. The button UART dump remains usable during a hung cache refill.

The CPU testbench also has [SystemVerilog functional coverage](docs/cpu-functional-coverage.md) with a reproducible named-bin report and CI gate.

The [architecture contract](docs/architecture-contract.md) freezes the target and flash allocation; the [simulation guide](docs/simulation.md) gives the regression commands. The [debug trace path](docs/debug.md) records retirement and traps. The CPU still halts on traps; privilege support and standard peripherals follow in checkpoint 10. [Checkpoint 9 board testing](docs/checkpoints/09-board-bringup.md) now passes at 50 MHz, including a CPU RESET retest: both caches map to BRAM, routed setup/hold timing passes, and DMA reports zero errors. The build uses 5,387 slices, 18 BRAM36 equivalents and four DSPs. CPU/cache use exceeds its slice allocation by 161 sites; that area review remains open for privilege/TLB integration.

## Development hosts

- Apple silicon Mac: repository work and lightweight development.
- OrbStack Ubuntu machines: available for Linux tooling after startup and verification.
- x86-64 Ubuntu PC with Vivado: synthesis, implementation, programming, and board measurements.

See [tooling inventory](docs/tooling.md) for what has actually been verified.

## License

Original project source is licensed under [Apache License 2.0](LICENSE). Third-party firmware, kernel, tools, and generated Vivado IP retain their own licenses and are not copied into this repository by default.
