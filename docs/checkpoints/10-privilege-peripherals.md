# Checkpoint 10: privilege, standard peripherals, and OpenSBI

Status: complete in RTL simulation on 2026-10-05. No FPGA timing, BRAM/resource,
physical UART, or Linux boot result is claimed. Boot ROM/loader implementation
also remains a later gate; the simulation starts directly in DDR firmware.
The initial implementation did not use checkpoint 9's board checkout.
Approved main and the final checkpoint 9 FPGA fixes were integrated and
retested on 2026-10-10, as recorded below; checkpoint 10 physical testing
remains pending.

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

## Remaining gates

Board UART pin arbitration, FPGA synthesis/timing/resources, and physical
execution remain board integration work. Linux boot requires Sv32 at checkpoint
11 and the later software/loader gates. This simulation gate is project-authored
coverage and generic firmware execution, not RISC-V architectural certification.

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
