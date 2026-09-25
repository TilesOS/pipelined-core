# Checkpoint 2: architecture and feasibility

Status: complete on 2026-09-25 under the revised checkpoint 2 pass condition. The architecture decisions are frozen in [`docs/architecture-contract.md`](../architecture-contract.md). Measured flash fit remains a checkpoint 13 gate because no bitstream or Linux software images have been built.

## Decisions recorded

- Target only Nexys A7-100T with RV32IMA_Zicsr_Zifencei, five in-order stages, M/S/U, Sv32, two 8 KiB physically tagged L1s, and trap-based Svade A/D handling.
- Reserve the top 8 MiB of 128 MiB DDR2 for uncached, handle-based DMA. Use standard 16550, SiFive CLINT and PLIC register layouts.
- Limit the fabric to 128-bit, in-order AXI4 INCR bursts with one read and one write outstanding per master. Cross from the 50 MHz fabric to the MIG user clock via asynchronous FIFOs.
- Boot from a bounded QSPI layout using a BRAM loader, SHA-256 integrity manifest, and LZ4-compressed kernel. Keep UART recovery.
- Set preliminary slice/BRAM/DSP ceilings and defer all utilization claims until Vivado synthesis and route.

## Evidence so far

- [Digilent board documentation](https://digilent.com/reference/_media/reference/programmable-logic/nexys-a7/nexys-a7_rm.pdf) specifies 128 MiB DDR2, 16 MiB QSPI, a 100 MHz oscillator, and a recommended 650 MT/s DDR2 configuration.
- [AMD UG470](https://docs.amd.com/v/u/en-US/ug470_7Series_Config) gives the 7A100T configuration length as 30,606,304 bits = 3,825,788 bytes, below the 4 MiB bitstream partition.
- `python3 scripts/check_flash_layout.py` validates contiguous partitions and reports 2,621,440 bytes (2.5 MiB) unallocated. It reports `BUDGET ONLY` without actual images and refuses to claim artifact fit.
- `python3 scripts/check_flash_layout.py --asset …` will check all six measured images and reject missing or oversized inputs. The full command and measured byte counts will be added when the images exist.
- A temporary-file gate check accepted six files at their exact partition caps and rejected a kernel one byte over its 6 MiB cap. The Python source parsed successfully with the local interpreter.

## Deferred measured gates

1. Build the six real assets and run the measured flash-size gate, including an actual Vivado programming `.bin` rather than only the UG470 nominal configuration length.
2. Confirm the generated MIG 128-bit AXI interface and user clock on the Ubuntu PC; checkpoint 8 also requires board bandwidth and timing.
3. Review the exact Linux/OpenSBI revisions before implementation of privilege and boot support.

The original checkpoint 2 text required actual images before implementation could produce them. The [plan decision log](../project-plan.md#decision-log) records the change: checkpoint 2 proves the bounded allocation and the checker, while checkpoint 13 rejects a boot image until the measured files all fit. This is a dependency correction, not a claim that those images already fit.
