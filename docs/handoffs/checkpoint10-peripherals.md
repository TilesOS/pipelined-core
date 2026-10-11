# Fresh-chat handoff: checkpoint 10 peripherals and privilege

Branch: `checkpoint10-peripherals` (renamed from
`codex/checkpoint10-peripherals`), originally based on checkpoint 9 `ec59ced`.
On 2026-10-10, integrated approved `main` at `142a347` (checkpoint 9
PR #2) so this branch includes the final FPGA cache/multiplier/CDC fixes
and checkpoint 9 board evidence. All eight combined regression gates pass;
see the [integration record](../checkpoints/10-privilege-peripherals.md#integration-with-approved-main-2026-10-10)
and [compact evidence](../checkpoints/evidence/10-main-integration.txt).
The original Mac worktree is
`/Users/tylermcclure/.codex/worktrees/checkpoint10-peripherals/pipelined-core`.
The original checkpoint 10 implementation ran in a separate cloud checkout.
The main integration is validated in the original Mac worktree using OrbStack.
Keep the checkpoint 9 checkout and measured bitstream available. The checkpoint 9
physical signoff applies to its recorded source commit; it does not establish
checkpoint 10 hardware results.

## Current state

Checkpoint 10 is complete in RTL simulation. Read
[the checkpoint record](../checkpoints/10-privilege-peripherals.md) for full
scope, commands, firmware pin, evidence, and remaining board/paging gates.

- CLINT and PLIC retain their directed tests. CLINT now also exposes `mtime`
  for the core's time CSR.
- `rtl/peripherals/uart16550.sv` implements the byte-spaced ns16550a, serial
  TX/RX, divisor/framing, 16-byte FIFOs, timeout and prioritized interrupts,
  line errors/overrun, THRE acknowledgement, and loopback.
- `checkpoint10_mmio` connects the exact-address adapter and all three devices,
  rejects invalid accesses without side effects, and reports explicit DECERR
  for unmapped/future apertures. `checkpoint10_top` connects this subsystem
  to checkpoint 9's CPU/cache/fabric/CDC MIG boundary.
- `rv32_slice` has opt-in M/S/U privilege, precise trap entry/return,
  delegation, vectored interrupts, software S interrupt pending bits,
  counter control, MPRV, and eight PMP entries checked before cache/MMIO
  requests. Legacy fixtures keep privilege disabled and first-trap halt.
- Failed dirty `FENCE.I` writeback still fails stop, even with privilege enabled.
  Cause 7 and fence-PC `tval` are diagnostics; dirty data and I-cache validity
  are retained. Ordinary precise access faults enter handlers.
- `config/dts/checkpoint10.dts` describes the standard devices, reserved
  firmware/DMA memory, and Bare-only CPU. `satp` remains WARL Bare;
  SFENCE.VMA and WFI are permitted no-ops subject to privilege/TVM/TW.
- Generic OpenSBI v1.7, pinned to
  `a32a91069119e7a5aa31e6bc51d5e00860be3d80`, executes on the real cached
  system, enters S mode, and passes SBI BASE, timer delivery, DTB, and resident
  firmware PMP isolation tests. The 133,884-byte `-Os` image fits the firmware
  allocation. Test payload/FDT addresses differ from production boot placement.

## Verification

```sh
bash scripts/run_checkpoint10_peripherals.sh
bash scripts/run_checkpoint10.sh
bash scripts/run_checkpoint10_opensbi.sh
bash scripts/run_checkpoint9.sh
bash scripts/run_checkpoint7.sh
bash scripts/run_checkpoint9_board.sh
bash scripts/run_cpu_coverage.sh
bash scripts/run_lockstep_smoke.sh --self-test
```

New Verilator builds have no default warnings. The integrated programs run
with three unrelated core/MIG clock ratios and seeded backpressure. The
firmware gate needs DTC and a PIE-capable RISC-V linker; CI installs
`gcc-riscv64-linux-gnu`. The bare-metal Debian linker rejects PIE, so the cloud
uses its GCC code generator with a local Linux BFD linker wrapper (documented
in the checkpoint record). Build products remain ignored under `build/`.

## Next work

1. Checkpoint 9 board bring-up is complete. Checkpoint 10's separate Nexys
   target, readback-verified test-image loader, shared console/trace UART and
   physical RX/PLIC payload are prepared. Follow
   [the board procedure](../checkpoints/10-board-bringup.md). First physical
   synthesis used 144/135 BRAM tiles (128 in the padded ROM). The ROM now stores
   firmware/payload compactly; the loader generates and verifies the DDR zero
   gap. Fresh synthesis passes at 84/135 BRAM tiles, with 64 ROM primitives
   and four CPU DSPs. Routing, timing/CDC/DRC review and physical execution
   remain pending. The operator
   controls Vivado locally on the Ubuntu PC and
   wants a new `/home/tyler/checkpoint10_board` project copied from the accepted
   `/home/tyler/checkpoint9_board`. Retain the original project/bitstream.
   Remeasure the CPU/cache area overage with privilege and peripherals.
2. Checkpoint 11: Sv32 TLBs/walker, Svade A/D faults, translated PMP/physical
   cacheability, SATP and SFENCE.VMA semantics, paging and stale-TLB tests.
   Keep the DTB Bare-only until those gates pass.
3. The board UART owner halts on BTNC, drains console TX, then retains trace
   ownership until CPU RESET. `checkpoint10_top` still exposes separate TX
   outputs for other integrations. Measure actual FPGA timing, resources/BRAM
   inference, repeatable serial execution and a complete trace dump.
4. Production loader/image addresses and Linux boot are later gates. This
   checkpoint proves bounded generic firmware execution, not Linux boot or
   architectural certification.
