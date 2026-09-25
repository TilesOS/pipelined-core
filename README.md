# Pipelined Core

A checkpoint-driven project to build a custom Linux-capable RV32IMA CPU, L1 caches, AXI interconnect, and INT8 matrix DMA accelerator for the Nexys A7-100T.

The [project plan](docs/project-plan.md) defines the architecture, 18 checkpoints, acceptance gates, and current progress. Start there before implementing a new subsystem.

## Current state

Checkpoints 1–4 are complete. The [architecture contract](docs/architecture-contract.md) freezes the target and flash allocation; the [simulation guide](docs/simulation.md) describes the Verilator and Spike retirement gate. The first RV32I pipeline slice and [debug trace path](docs/debug.md) are verified in simulation. The CPU is still a zero-wait-memory subset, with no caches, board integration, or accelerator RTL.

## Development hosts

- Apple silicon Mac: repository work and lightweight development.
- OrbStack Ubuntu machines: available for Linux tooling after startup and verification.
- x86-64 Ubuntu PC with Vivado: synthesis, implementation, programming, and board measurements.

See [tooling inventory](docs/tooling.md) for what has actually been verified.

## License

Original project source is licensed under [Apache License 2.0](LICENSE). Third-party firmware, kernel, tools, and generated Vivado IP retain their own licenses and are not copied into this repository by default.
