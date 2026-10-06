# Fresh-chat handoff: checkpoint 10 peripheral work

This is independent of checkpoint 9 board bring-up. Keep the board-focused
chat on the existing checkpoint 9 checkout. This branch is
codex/checkpoint10-peripherals, based on checkpoint 9 commit ec59ced.
Managed worktree:
/Users/tylermcclure/.codex/worktrees/checkpoint10-peripherals/pipelined-core.

## Completed in this branch

- rtl/peripherals/clint.sv: single-hart SiFive-layout CLINT at
  0x0200_0000, with MSIP, 64-bit mtimecmp/mtime, and a 50-cycle timer
  divider for a 1 MHz tick at the planned 50 MHz core clock. Aligned 32-bit
  word accesses only; invalid addresses, sizes, or write strobes report an
  error without changing state.
- rtl/peripherals/plic.sv: two-source PLIC, with UART as source 1 and DMA as
  source 2. M and S contexts have priority, pending, enable, threshold, and
  claim/complete registers at the standard SiFive offsets. Level-triggered
  gateway state prevents repeated delivery while a source is in service.
  Notification obeys each threshold; a claim can still poll a pending,
  enabled source below that threshold, per the ratified PLIC specification.
- Directed self-checking simulations cover timer division, safe RV32
  mtimecmp writes, 64-bit rollover, MSIP, PLIC priority/ties, both contexts,
  claim/complete ownership, level re-pending, invalid accesses, and held
  responses. Run bash scripts/run_checkpoint10_peripherals.sh from the
  worktree with Verilator. Verilator 5.032 passes without warnings.
- The repository CI has a separate peripheral simulation job. The existing
  coverage job also installs libfl-dev, which supplies FlexLexer.h for its
  pinned Verilator source build.

The module ports use the exact-address 32-bit device request/response
interface exposed by rtl/bus/axi_peripheral_adapter.sv. The CPU/cache
integration, board timing, and OpenSBI tests have not yet been run on these
peripherals. Checkpoint 10 in docs/project-plan.md remains pending.

## Next work in the fresh chat

1. Add and test an ns16550a UART with byte register spacing and the planned
   50 MHz reference/115200 baud default. Include receive, transmit, and
   interrupt-identification behavior needed by OpenSBI/Linux.
2. Build the MMIO decoder around axi_peripheral_adapter, CLINT, PLIC, UART,
   and explicit errors for unmapped addresses. Wire it to
   checkpoint9_top.peripheral_req/peripheral_rsp.
3. Route msip, mtip, meip, and seip to the CPU; implement precise
   interrupt sampling, M/S/U privilege, trap entry/return, delegation, and
   eight PMP entries. Review checkpoint 9's fail-stop FENCE.I writeback
   policy when trap routing is added.
4. Produce the device tree and test timer-compare writes, interrupts, trap
   paths, and generic OpenSBI. Do not mark checkpoint 10 complete before
   those gates pass.

Relevant sources: [RISC-V machine timer/interrupt rules](https://docs.riscv.org/reference/isa/priv/machine.html)
and [ratified PLIC register/claim rules](https://github.com/riscv/riscv-plic-spec/blob/master/riscv-plic.adoc).
