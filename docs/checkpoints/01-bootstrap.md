# Checkpoint 1: repository and tooling

Status: awaiting verification of the Ubuntu PC's Vivado installation.

## Delivered

- Created the public [TilesOS/pipelined-core](https://github.com/TilesOS/pipelined-core) repository with `main` as its default branch.
- Preserved the complete project plan in [`docs/project-plan.md`](../project-plan.md), linked it from the README, added Apache-2.0 licensing and a GitHub Actions skeleton.
- Initialized the local Git repository and aligned it with the published `main` branch. The initial published tree matched the local tree exactly (`76f92be5474c1775163886e21aee23f203b7e390`).
- Inventoried the Mac and both OrbStack Ubuntu machines in [`docs/tooling.md`](../tooling.md).

## Evidence

- Local documentation assertions passed: README links the plan, all 18 checkpoints appear, and the Apache license is present.
- `git diff --cached --check` passed before the initial local commit.
- [First GitHub Actions repository check](https://github.com/TilesOS/pipelined-core/actions/runs/36062920339) completed successfully.
- No CPU, cache, interconnect, DMA, or board RTL has been started.

## Open item

The Ubuntu PC is reported to have Vivado but is not connected to this workspace. Record `uname -m` and `vivado -version` output before marking checkpoint 1 complete or starting FPGA-dependent work.

## Publishing method

The existing GitHub connection published the project files to `TilesOS/pipelined-core`. The local branch was then aligned to the identical published tree.
