# Checkpoint 10: privilege, standard peripherals, and OpenSBI

Status: complete in RTL simulation on 2026-10-05 and on the Nexys A7-100T
on 2026-10-11. Source-specific FPGA timing/resource review, physical OpenSBI,
S-mode timer/PMP, UART RX/PLIC, CPU RESET retest, complete trace and post-trace
reset recovery pass, including the UART full-FIFO fix at `5e0fb45`; see
[latest board acceptance](10-board-bringup.md#uart-fix-physical-board-acceptance-2026-10-11).
The CPU/cache area review remains open. Sv32, Linux boot, production QSPI loading and
UART recovery remain later gates; the original simulation starts directly in
DDR firmware, while the board proof copies a test-image ROM into DDR.
The initial implementation did not use checkpoint 9's board checkout.
Approved main and the final checkpoint 9 FPGA fixes were integrated and
retested on 2026-10-10, as recorded below; subsequent physical testing passes
on the source/image identities recorded in the board procedure.

## Delivered

- `uart16550`: byte-spaced ns16550a registers at `0x10000000`, programmable
  divisor and 5–8 bit framing, parity, break, stop bits (including 1.5 for five-bit
  words), receive/transmit, optional 16-byte FIFOs, trigger levels, character
  timeout, line errors/overrun, THRE acknowledgement, modem status, and internal
  loopback. Reset is 8N1 with divisor 27: 50 MHz / 432 = 115740.7 baud, 0.47%
  above nominal 115200. There are no external modem pins; CTS/DSR/DCD are
  asserted and RI is low outside loopback. Invalid sizes/addresses/strobes
  return errors without register side effects.
- `checkpoint10_mmio`: the exact-address AXI adapter, CLINT, PLIC, UART,
  interrupt wiring, and held response ownership. UART is source 1; the exposed
  DMA interrupt is source 2. Mapped invalid requests return SLVERR, while
  unmapped and future DMA/QSPI/debug devices return DECERR. AXI requests with
  invalid alignment or strobes outside their addressed lanes never reach a
  device. Reads with side effects happen once at device admission.
- `checkpoint10_top` connects these devices to the existing checkpoint 9
  CPU/cache/fabric/CDC MIG boundary. `msip`, `mtip`, `meip`, `seip`, and the
  64-bit CLINT time reach the core. Console TX and independent hardware trace
  TX are separate boundary outputs; sharing a physical board pin requires
  the later board UART arbiter. Neither the checkpoint 8 board top nor its
  measured build changes here.
- Opt-in M/S/U privilege in `rv32_slice`, enabled by `checkpoint10_top`.
  Trap entry, MRET/SRET, CSR privilege checks and WARL fields, S CSR aliases,
  delegation, direct/vectored interrupts, software S pending bits, counter
  enables/inhibit, and MPRV follow the privileged v1.12 base behavior used by
  this platform. Optional environment features are hardwired off; `mconfigptr`
  is zero. `misa` is fixed RV32IMA/S/U. `satp` is Bare-only and SFENCE.VMA is a
  legal no-op subject to privilege/TVM. WFI is a legal no-op subject to
  privilege/TW. Sv32 remains checkpoint 11.
- Eight four-byte-granularity PMP entries, OFF/TOR/NA4/NAPOT, first-match
  permissions, full-access matching, lock semantics including a preceding
  TOR bound, and MPRV. Checks run before instruction cache requests and data
  operations, including cache hits and MMIO. Trap entry/return clears LR.
- Interrupts stop new fetch and drain admitted instructions, memory responses,
  and stores before entry. The saved PC is the next architectural instruction,
  including branch targets. A synchronous exception takes precedence and
  kills younger stages. Interrupt events use instruction zero and do not
  increment `minstret`; retirement records carry the prior privilege.
- Device tree and a pinned, size-optimized generic OpenSBI v1.7 configuration.
  The DTB describes hart 0, the 1 MHz timer, both PLIC contexts, 50 MHz UART,
  128 MiB DDR, resident firmware, and the uncached 8 MiB DMA pool. It advertises
  Bare mode, not Sv32. Firmware source is downloaded under ignored `build/`
  and retains its BSD license.

The legacy checkpoint 4/9 test configurations keep `ENABLE_PRIVILEGE=0` and
halt on their first trap, preserving the existing Spike regression protocol.
For failed dirty writeback during FENCE.I, both configurations remain fail-stop:
cause 7, fence PC as tval, retained dirty data, and no I-cache invalidation.
This platform failure cannot safely enter an ordinary recovery handler with
possibly stale executable memory. Other precise memory faults enter handlers.

## Evidence and reproduction

Verilator 5.032, RV32 GCC 14.2, DTC 1.7.2, and pinned Spike 1.1.0 on the managed
Debian 13 cloud workspace:

```sh
bash scripts/run_checkpoint10_peripherals.sh
bash scripts/run_checkpoint10.sh
bash scripts/run_checkpoint10_opensbi.sh
bash scripts/run_checkpoint9.sh
bash scripts/run_checkpoint7.sh
bash scripts/run_core_slice.sh
bash scripts/run_checkpoint6.sh
```

Default Verilator builds have no warnings. The device gate checks CLINT/PLIC
regressions, serial TX/RX, UART FIFO order/trigger/timeout, parity/break/overrun,
loopback, five-bit framing, invalid access side effects, narrow AXI lanes,
backpressure, unmapped errors, timer compares, and UART-to-PLIC ownership.

Three programs each pass at core/MIG half-periods 5/7, 3/11, and 11/3 with
seeded backpressure. They exercise M/S/U ECALL and illegal CSR paths, CSR
aliases, vectored M/S delivery, MSIP-before-MTIP priority, UART external IRQ,
MPRV, PMP R/W/X and overlap priority, all eight locked NA4 entries, TOR-bound
locking, NAPOT/full-space regions, unmapped MPRV access, LR invalidation, and
CPU recovery from DECERR/device errors. An injected failed FENCE.I writeback
also proves that privilege does not turn that failure into unsafe recovery.

The actual generic firmware reaches the S payload through the real cached CPU,
MMIO, fabric, and asynchronous memory boundary. Its serial output reports
privilege v1.12, eight PMP entries, 32 PMP address bits, MIDELEG `0x222`, and
S-mode next stage. The payload verifies the DTB, SBI BASE calls, SBI TIME
MTIP-to-STIP delivery, S timer entry/return, denied reads/writes of resident
firmware, and a subsequent working SBI call. It emits
`CHECKPOINT10 SBI TIMER/PMP PASS` over the actual UART.

OpenSBI is pinned to `a32a91069119e7a5aa31e6bc51d5e00860be3d80` (v1.7),
built at `-Os` with only this platform's device drivers. The measured firmware
binary is **133,884 bytes**, under the 256 KiB allocation. Its complete runtime
region including heap/scratch fits the DTB's 256 KiB reservation. The test
S payload at `0x80040000` and relocated DTB at `0x80060000` are simulation
fixtures; production boot placement remains the architecture contract.

OpenSBI requires a PIE-capable linker. CI installs
`gcc-riscv64-linux-gnu` in addition to the existing bare-metal compiler.
The cloud run uses GCC 14.2's bare-metal code generator with Debian binutils
2.44's RISC-V Linux BFD linker through a local wrapper:

```sh
OPENSBI_CC=/workspace/.cloud-setup/pipelined-core/pie-linker/gcc \
OPENSBI_CROSS_COMPILE=riscv64-unknown-elf- OPENSBI_LD=riscv64-linux-gnu-ld \
    bash scripts/run_checkpoint10_opensbi.sh
```

The earlier cached Spike, fault, contention, calibration restart, stalled-debug,
AXI, zero-wait CPU and M/A/CSR gates pass. Saved compact output is in
[evidence/10-simulation.txt](evidence/10-simulation.txt).

## Board acceptance and remaining gates

The [checkpoint 10 board target](10-board-bringup.md) now provides UART pin
ownership, a readback-verified DDR test-image loader and a serial RX/PLIC
payload. The fifth route at implementation `5b74119`, retaining `74d26b9`
synthesis/image, fits at 84/135 BRAM tiles, passes 50 MHz timing
(+0.308/+0.017/+0.206 ns) and confirms FDRE CPU reset. The targeted per-cell
power-gating exclusion clears the RAM warnings; both tag enables use only
their registered RTL startpoint. Pin/exception and CDC inventory review passes.
The operator's three boot captures pass OpenSBI/S timer/PMP and physical
UART RX/PLIC milestones, including CPU RESET retest and post-trace reset
recovery. A complete 256-record S-mode trace and the reported LED on-set
0/1/3 complete the functional board gate; see
[physical evidence](evidence/10-board-acceptance/review.txt).
CPU/cache area remains 4,710 sites against 3,000; retain that review for Sv32
and accelerator growth. The recorded board build retains its simulation evidence.
Linux boot requires Sv32 at checkpoint
11 and the later software/loader gates. This simulation gate is project-authored
coverage and generic firmware execution, not RISC-V architectural certification.

## PMP unit-test scheduling on CI, 2026-10-11

The Ubuntu 24.04 CI `privilege` job at `3f3e75f` failed the PMP interval unit
test under Verilator 5.020 at address `0x8000400f`, size 1 (two bytes), M mode,
read/write permissions: expected denial, observed allowance. The same test
passed under the local Verilator 5.032. Reproducing with Ubuntu's 5.020 package
confirmed that the clock tied low in this isolated fixture caused generated
NAPOT-mask logic to run only during initial settling; subsequent hierarchical
CSR-bank writes left those masks stale.

The fixture now clocks the core, performs a reset cycle, holds it halted and
waits a full clock period after each test CSR update. This keeps the real
checker combinational logic active while preventing instruction execution from
overwriting the stimulus. The independent interval reference, seed, permission
assertions and all 106,808 checks are unchanged. Both simulator versions pass
the fixture, and the full privilege gate passes with a fresh Verilator 5.020
build. See [compatibility evidence](evidence/10-ci-pmp-scheduling.txt).
This testbench-only correction changes no RTL, firmware, Vivado constraint or
workflow, so the recorded physical board build remains applicable.

## UART full-FIFO pop/write review fix, 2026-10-11

A THR write accepted while a full TX FIFO pops into the idle serializer used
to return success while discarding the new byte. `tx_push` now allows either
available capacity or a simultaneous `tx_pop`. The existing simultaneous
count/head/tail updates preserve the queued byte order, including the full
16-byte FIFO's shared head/tail slot.

The directed UART regression fills the queue behind an active serializer,
aligns a THR write with its next pop, and checks the successful held response,
unchanged full occupancy, every serial byte in order, and THRE assertion and
acknowledgement after draining. It covers FIFO depth 16 and the disabled
FIFO's depth 1. Both cases fail against the preceding RTL. The full peripheral/
MMIO gate passes with Verilator 5.032; fresh UART and MMIO builds also pass
with CI's Verilator 5.020. All of these builds have no default warnings.

Fresh synthesis and routing at clean `5e0fb45` pass setup/hold/pulse timing
(+0.932/+0.024/+0.206 ns), retain FDRE reset and the registered tag-RAM enables,
and clear REQP-1839/1840. Image hashes, pin assignments, clock definitions and
timing exceptions match the accepted fifth route. The complete CDC inventory
has the same rule totals and source families. UART timeout DSP pipelining
guidance increases to 15 DPIR-1 findings on the same DSP; other methodology
and DRC rule counts are retained. CPU/cache area is 4,513/3,000 slices, with
6,874 total device slices and 84/135 BRAM tiles. Both exact-source CI workflows
pass. See [UART-fix route review](evidence/10-uart-fix-route/review.txt).

Physical boot/reset, UART/PLIC, complete S-mode trace and post-trace recovery
for `5e0fb45` now pass. All three boot captures are identical to the earlier
accepted console sequence; the operator confirms LEDs 0/1/3 on and 2 off.
Reports/image identity match the reviewed UART-fix route. The recorded new
bitstream SHA-256 is
`cb7097546110f510456e53b436bc8a4467868c604f58183ee025b5ad42840155`.
See [UART-fix physical acceptance](evidence/10-uart-fix-board-acceptance/review.txt).
Older physical acceptance remains scoped to its recorded source and bitstream.
This evidence update changes no RTL or constraints and requires no rebuild.

## Integration with approved main, 2026-10-10

Merged `main` at `142a34783f2ac167b09d3cb998e740e936f03f2d` (checkpoint 9
PR #2) into checkpoint 10 at `42f2b18`. Retained the registered cache RAM
controls, byte-enable stores, shared RV32 multiplier, CDC constraints,
board harness and recorded checkpoint 9 physical evidence. The opt-in
privilege/PMP and standard peripherals remain intact.

Resolved the CI conflict by keeping all six jobs, and combined the README and
plan records so checkpoint 9 is complete on the board while checkpoint 10
is complete in simulation. The CPU multiplier change merged automatically
and was reviewed. Updated the legacy checkpoint 9 smoke harness for the new
interfaces: interrupt/time inputs are tied to zero, retire_priv is unused,
and the adapter's decode-error input is tied low to preserve its SLVERR behavior.
The initial board lint found the missing adapter input; the corrected build
and complete smoke gate pass without default Verilator warnings.

All eight combined regression gates pass on OrbStack with Verilator 5.032
(5.052 for CPU coverage), bare-metal GCC 14.2.0 and Linux RISC-V GCC 15.2.0:
cache/CPU/Spike, ROM/board/UART/calibration-restart, AXI, CLINT/PLIC/UART/MMIO,
privilege/PMP/MMIO faults, failed FENCE.I policy, pinned OpenSBI and CPU
coverage/comparator self-tests. CPU coverage reaches 243/243 named bins and
96/96 included hazard/trap/stage cross tuples. These are project-authored
regressions, not architectural certification. OpenSBI remains pinned to
`a32a91069119e7a5aa31e6bc51d5e00860be3d80`; this toolchain's firmware is
133,892 bytes, under 256 KiB, and the real cached simulation reaches the
S-mode payload and passes SBI BASE, timer delivery and resident PMP isolation.

See [the integration evidence](evidence/10-main-integration.txt) for commands
and compact results. Checkpoint 9's physical measurements still identify
its original measured RTL and bitstream. This merge does not establish
checkpoint 10 timing, area or physical execution; its console/debug UART
selection and firmware startup path need board integration. The recorded
CPU/cache allocation overage must be remeasured with privilege/peripherals.
