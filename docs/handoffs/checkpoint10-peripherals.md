# Fresh-chat handoff: checkpoint 10 peripherals and privilege

Branch: `codex/checkpoint10-peripherals`, based on checkpoint 9 `ec59ced`.
The original Mac worktree is
`/Users/tylermcclure/.codex/worktrees/checkpoint10-peripherals/pipelined-core`.
This continuation ran in the separate cloud checkout `/workspace/pipelined-core`.
Keep the checkpoint 9 checkout available for board bring-up. No board checkout,
checkpoint 8 board RTL, or measured board build was modified.

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
bash scripts/run_core_slice.sh
bash scripts/run_checkpoint6.sh
```

New Verilator builds have no default warnings. The integrated programs run
with three unrelated core/MIG clock ratios and seeded backpressure. The
firmware gate needs DTC and a PIE-capable RISC-V linker; CI installs
`gcc-riscv64-linux-gnu`. The bare-metal Debian linker rejects PIE, so the cloud
uses its GCC code generator with a local Linux BFD linker wrapper (documented
in the checkpoint record). Build products remain ignored under `build/`.

## Next work

1. Board bring-up continues independently in checkpoint 9's checkout.
2. Checkpoint 11: Sv32 TLBs/walker, Svade A/D faults, translated PMP/physical
   cacheability, SATP and SFENCE.VMA semantics, paging and stale-TLB tests.
   Keep the DTB Bare-only until those gates pass.
3. Later board integration must arbitrate console/debug TX onto the physical
   UART pin; checkpoint10_top exposes separate console and debug TX outputs.
   Measure actual FPGA timing, resources/BRAM inference, and serial execution.
4. Production loader/image addresses and Linux boot are later gates. This
   checkpoint proves bounded generic firmware execution, not Linux boot or
   architectural certification.
