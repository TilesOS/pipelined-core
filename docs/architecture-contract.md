# Architecture contract (checkpoint 2)

Status: frozen for implementation on 2026-09-25. A change to an address, externally visible register, ISA feature, or bus rule requires a dated entry in `docs/project-plan.md` and a matching test update.

## Target and ISA

- Board: Nexys A7-100T, `XC7A100T-1CSG324C`; one 128 MiB, 16-bit DDR2 device and one 16 MiB QSPI flash. This is not a target for the 50T variant.
- One hart (`hartid = 0`), RV32 little endian, `rv32ima_zicsr_zifencei`, 32-bit instruction alignment. No C, F, D, vector, or speculative execution. Illegal instructions, misaligned instruction/data accesses, and unsupported CSR operations trap precisely. Software FP is used for Linux and the classifier.
- M/S/U privilege, Sv32 and Bare modes, direct and vectored trap entry where architecturally required, eight PMP entries, 64-bit `mcycle`/`minstret`, and a 64-bit 1 MHz `mtime`. Implement the mandatory behavior of the chosen privileged ISA before advertising it in `misa` or the device tree. OpenSBI requires at least RV32IMA_Zicsr, S mode, and direct `mtvec` ([OpenSBI requirements](https://github.com/riscv-software-src/opensbi/blob/master/docs/platform_requirements.md)).
- Five logical pipeline stages: IF, ID, EX, MEM, WB. One instruction issues and retires at most once per cycle. IF waits for synchronous I-cache/tag reads; MEM waits for D-cache/TLB/AXI; stalls hold the affected and younger stages. Branches resolve in EX; taken branches and traps kill younger work. Architectural state and memory side effects commit in order at retirement. A single-entry committed store buffer may drain afterward, but fences and atomics wait for it. Interrupts are sampled between retired instructions.
- A 256-entry circular record of retired PC, instruction, privilege, exception/interrupt cause, and trap value is independent of pipeline forward progress. A debounced button triggers a UART dump through a debug arbiter even if the core is stalled. Reserve ILA probes for per-stage valid/stall/kill, retirement PC/cause, cache miss/writeback, AXI valid/ready, and MIG calibration.

## Address map and physical memory attributes

All addresses are physical after Sv32 translation. Unlisted addresses return an access fault; no address aliasing. The decoder and linker scripts use these exact ranges.

| Range | Function | CPU attribute | Notes |
|---|---|---|---|
| `0x0000_0000`–`0x0000_FFFF` | 64 KiB boot ROM aperture | uncached, read/execute | BRAM loader, reset PC `0x0000_0000`; writes fault. |
| `0x0200_0000`–`0x0200_FFFF` | CLINT | uncached | SiFive layout: `msip` `+0x0000`, `mtimecmp` `+0x4000`, `mtime` `+0xBFF8`. |
| `0x0C00_0000`–`0x0FFF_FFFF` | PLIC aperture | uncached | SiFive PLIC register layout; context 0=M, context 1=S; source 1=UART, 2=matrix DMA. |
| `0x1000_0000`–`0x1000_0FFF` | ns16550a UART | uncached | 8-bit registers at byte offsets, 50 MHz reference, 115200 baud default, PLIC source 1. |
| `0x1001_0000`–`0x1001_0FFF` | matrix DMA control | uncached | Register ABI fixed at checkpoint 14; PLIC source 2. |
| `0x1002_0000`–`0x1002_0FFF` | QSPI controller | uncached | Loader access; post-configuration clock uses `STARTUPE2`. |
| `0x1003_0000`–`0x1003_0FFF` | trace/debug control | uncached | UART dump also has a hardware button trigger. |
| `0x8000_0000`–`0x877F_FFFF` | Linux DDR2, 120 MiB | cacheable | DMA never targets this range in v1. |
| `0x8780_0000`–`0x87FF_FFFF` | DMA pool, 8 MiB | uncached | Device-tree reserved memory, exposed only via opaque driver handles. |

Each L1 is 8 KiB, two-way, 32-byte lines, physically tagged (128 sets, 256 total lines). I-cache is read-only; D-cache is write-back/write-allocate. Both are blocking in v1. The page walker reads PTEs through the D-cache path so it observes CPU PTE stores; `SFENCE.VMA` drains older stores before invalidating matching TLB entries. Svade A/D semantics are trap based, so the walker never writes a PTE ([RISC-V supervisor specification](https://docs.riscv.org/reference/isa/priv/supervisor.html)). MMIO and the DMA pool bypass both L1s based on **physical** address, including after virtual translation. DMA has no coherent access to cached DDR. Linux cannot map an alternate cached alias of the DMA pool.

`FENCE` drains committed stores and outstanding memory transactions. `FENCE.I` drains stores, writes back **all** dirty D-cache lines, waits for completion, invalidates the I-cache, and flushes/refetches the front end. `SFENCE.VMA` drains older page-table stores and invalidates the requested TLB entries. LR/SC and AMOs serialize through the D-cache; a reservation is cleared by an intervening conflicting store, trap return, or context change. Unaligned atomic operands trap. Tests must include self-modifying code, `exec` after cached writes, A/D faults, stale TLBs, and uncached DMA aliases.

The RV32 `mtimecmp` programming contract is a high-half write of `0xFFFF_FFFF`, then the desired low half, then the desired high half. This prevents an intermediate compare value from spuriously asserting the timer interrupt. Directed tests exercise the sequence at low-half rollover and with an already pending timer interrupt.

## AXI and clocks

- Board oscillator: 100 MHz. PLL/MMCM creates a 50 MHz core, cache, fabric, UART, and DMA domain. The CLINT timer increments at 1 MHz. MIG generates its own user clock; with Digilent's recommended 650 MT/s DDR2 setting and 4:1 PHY ratio, the planned 128-bit user interface runs at about 81.25 MHz. Vivado's generated MIG configuration is the authority for the actual clock and port widths ([Digilent DDR2 settings](https://digilent.com/reference/_media/reference/programmable-logic/nexys-a7/nexys-a7_rm.pdf), [AMD MIG AXI parameters](https://docs.amd.com/r/en-US/ug586_7Series_MIS/AXI4-Slave-Interface-Parameters)).
- Custom synthesizable fabric offers AXI4's five independent ready/valid channels, 32-bit addresses, 128-bit DDR data, byte strobes, aligned INCR bursts of 1–16 beats, no WRAP/FIXED/exclusive bursts, no interleaving, and in-order responses per master. Four fixed master IDs identify I-cache refill, D-cache writeback/refill and walker, loader/debug, and DMA. At most one read and one write transaction per master may be outstanding. A width bridge converts CPU byte/halfword/word accesses to 128-bit beats; memory operations may not cross a 4 KiB AXI boundary.
- The matrix DMA has a 128-bit read/write path to the fabric. Fabric arbitration is fair round-robin at burst boundaries, with bounded wait under continuous request. MMIO uses single-beat accesses through a decoded peripheral adapter. Invalid regions produce DECERR. No coherence is implied by AXI ordering.
- The MIG boundary uses dual-clock, Gray-pointer FIFOs with synchronized asynchronous-reset release for commands, write data, read data, and responses. Do not sample multibit payloads across domains without a FIFO handshake. Hold the core and masters in reset until MIG calibration completes; a failed calibration is reported over the debug UART path. Randomized reset, unrelated clock ratios, backpressure, concurrent masters, and data scoreboards gate checkpoint 7.
- At 50 MHz, a 128-bit master has an **800 MB/s theoretical port ceiling**; the board's 16-bit, 650 MT/s DDR2 link has a **1.3 GB/s raw ceiling**. Neither number is a performance promise. Checkpoint 8 measures sustained traffic and checkpoint 15 sizes accelerator tiles from that result.

## Boot and software placement

The FPGA configures from flash address zero. A BRAM-resident first-stage loader waits for DDR calibration, validates a versioned manifest and SHA-256 hashes, copies OpenSBI and the DTB, decodes a host-produced LZ4 kernel block into DDR, copies the compressed initramfs, and transfers to OpenSBI. SHA-256 is an integrity check, **not** a secure-boot signature. On bad magic, length, hash, or decode, the loader reports the fault over UART and accepts a replacement image over a bounded UART recovery protocol. The QSPI read path must work with either flash variant named by Digilent.

The image loading contract is: OpenSBI at `0x8000_0000`, DTB at `0x8070_0000`, decompressed Linux `Image` at `0x8080_0000`, and compressed initramfs at `0x8500_0000`. The kernel is 4 MiB aligned as required for RV32 ([Linux boot requirements](https://docs.kernel.org/arch/riscv/boot.html)). The unpacked kernel must end before `0x8500_0000`; the initramfs must end before `0x8780_0000`. The boot manifest records packed and unpacked lengths and hashes; a build check enforces these limits. OpenSBI enters S-mode Linux with `a0=0`, `a1=DTB`, and `satp=0`; the DTB reserves resident OpenSBI and the 8 MiB DMA pool. Linux and Buildroot revisions, config, and actual compressed sizes are frozen when those images are first built.

## Flash and FPGA budgets

The [machine-readable flash layout](../config/flash-layout.json) and [size checker](../scripts/check_flash_layout.py) are the source of truth for offsets and caps. Flash is 16 MiB. The fixed partition ends at `0xD8_0000`, leaving **2.5 MiB unused**, more than the required 1 MiB. Partitions are: bitstream 4 MiB; manifest 64 KiB; OpenSBI 256 KiB; DTB 64 KiB; LZ4 kernel 6 MiB; initramfs 3 MiB; model 128 KiB. The XC7A100T configuration stream is 30,606,304 bits, or 3,825,788 bytes, which fits the 4 MiB partition with 368,516 bytes of margin ([AMD UG470](https://docs.amd.com/v/u/en-US/ug470_7Series_Config)). No Linux artifacts exist yet; the allocation proves capacity **conditional on those caps**, not their actual sizes. Checkpoint 13 must measure the raw programming `.bin` and all software artifacts with the checker before accepting a QSPI boot image.

The XC7A100T provides 15,850 slices, 135 BRAM36 equivalents (4,860 Kb), and 240 DSP48E1 slices ([AMD DS180](https://docs.amd.com/api/khub/documents/2LByHkO~nSZXcei2D55fTg/content)). The following are design ceilings, not utilization reports:

| Block | Slice ceiling | BRAM36 ceiling | DSP ceiling |
|---|---:|---:|---:|
| CPU, TLBs, and L1s | 3,000 | 30 | 8 |
| MIG and clocking | 3,000 | 25 | 0 |
| AXI, width bridge, CDC | 2,500 | 15 | 0 |
| Peripherals, loader, trace | 1,500 | 12 | 0 |
| Matrix DMA, up to 8×8 | 2,000 | 30 | 72 |
| **Allocated ceiling** | **12,000** | **112** | **80** |
| **Unallocated reserve** | **3,850** | **23** | **160** |

Checkpoint 8 replaces these assumptions with post-route utilization and timing. Any block exceeding its allocation triggers review before adding more accelerator lanes. A 64-MAC tile is an upper option, not a commitment; checkpoint 16 retains only the largest tile meeting timing and measured batch-8 utilization. Model weights (50,816 INT8 bytes for 784×64 and 64×10) stay in the uncached DDR pool across inference calls, rather than occupying BRAM or being recopied by the CPU.

## Open gates and change control

1. **Measured flash fit at checkpoint 13:** build the real bitstream, OpenSBI, DTB, LZ4 kernel, initramfs, and model; run the size checker on all six files. The checker enforces each cap and the 2.5 MiB reserved spare. The budget is proven now; actual artifact sizes remain unproven until then.
2. **MIG compatibility:** generate the DDR2 IP in Vivado 2026.1 on the Ubuntu PC and confirm the 128-bit AXI width, actual UI clock, calibration, part support, and pinout before checkpoint 8.
3. **Linux compatibility:** pin a kernel revision and inspect its RV32 Svade, `FENCE.I`, 16550, CLINT, PLIC, and no-FPU configuration paths before checkpoint 13. Do not claim Linux boot from architecture review alone.
