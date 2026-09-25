# Nexys A7 RV32 Linux CPU and matrix DMA

## Summary

Implement the system through the 18 checkpoints below, committing and reviewing test evidence after each one. Checkpoint 1 creates this document, links it from the README, initializes Git, and creates the public `pipelined-core` GitHub repository. Update this document as checkpoints are completed or decisions change.

## Architecture

- Build a five-stage, in-order RV32IMA CPU with Zicsr, Zifencei, M/S/U modes, Sv32, and separate 8 KiB two-way L1 caches. Fetch may stall for synchronous cache reads.
- Use a custom, restricted AXI4 fabric: one ID per master, incrementing bursts, in-order responses, a CPU width bridge, and a 128-bit MIG interface across a tested asynchronous clock crossing. Use Vivado IP for DDR2 and clocks. ([AMD MIG interface specification](https://docs.amd.com/r/en-US/ds176_7Series_MIS/AXI4-Slave-Interface-Features))
- Provide an `ns16550a` UART, SiFive-compatible CLINT and PLIC, a matching device tree, and generic OpenSBI support. Test safe RV32 timer-compare writes. ([OpenSBI generic platform](https://github.com/riscv-software-src/opensbi/blob/master/docs/platform/generic.md))
- Determine cacheability by physical address. Reserve the top 8 MiB of DDR2 as uncached DMA memory. Use trap-based Svade A/D handling. Make `FENCE.I` complete D-cache writeback, I-cache invalidation, and fetch flush. ([Svade specification](https://docs.riscv.org/reference/isa/priv/supervisor.html), [FENCE.I specification](https://docs.riscv.org/reference/isa/unpriv/zifencei.html))
- Boot from the board’s 16 MiB QSPI flash through a verified image manifest and BRAM loader; retain UART recovery. Use `STARTUPE2` for the post-configuration flash clock. ([Nexys A7 manual](https://digilent.com/reference/_media/reference/programmable-logic/nexys-a7/nexys-a7_rm.pdf))
- Expose the matrix accelerator through `/dev/matmul` using opaque buffer handles. Never accept physical addresses from userspace. Load model weights once; run the INT8 classifier in batches of at least eight images.

## Checkpoints

| # | Deliverable and pass condition | Status |
|---|---|---|
| 1 | **Repository and plan:** save this plan as `docs/project-plan.md`; link it from README; add Apache-2.0 license and CI skeleton; initialize Git and push the public GitHub repo. Inventory Mac, OrbStack, and Ubuntu/Vivado tools. | Complete; [record](checkpoints/01-bootstrap.md) |
| 2 | Freeze ISA, pipeline, memory map, AXI subset, clocks, flash layout, and resource budget. Prove the bitstream and compressed software images fit flash with at least 1 MiB spare. | Pending |
| 3 | Build Verilator simulation and a retirement-by-retirement Spike comparator that stops at the first divergent instruction with architectural state and memory effects. | Pending |
| 4 | Implement the first five-stage RV32I slice, a 256-entry retirement/trap ring, independent button-triggered UART dump, and defined ILA probes. Prove a forced hang remains diagnosable. | Pending |
| 5 | Complete RV32I hazards, branches, exceptions, and precise retirement; pass directed, randomized, and architectural tests in lockstep. | Pending |
| 6 | Add M/A instructions, LR/SC, AMOs, CSRs, and fences; pass contention and lockstep tests. | Pending |
| 7 | Implement AXI fabric, width bridge, and clock crossing; pass randomized clock, reset, backpressure, burst, and concurrent-master tests. | Pending |
| 8 | Bring up MIG and 128-bit DDR transfers on the board; meet 50 MHz timing and measure sustained bandwidth with and without CPU traffic. | Pending |
| 9 | Add caches, physical-address cacheability, atomics, and full `FENCE.I`; pass eviction, executable-page, and uncached-window tests. | Pending |
| 10 | Add privilege, PMP, standard UART/CLINT/PLIC, and device tree; pass trap, interrupt, timer-compare, and OpenSBI tests. | Pending |
| 11 | Add Sv32 TLBs, read-only walker, Svade faults, and `SFENCE.VMA`; pass paging and stale-TLB tests. | Pending |
| 12 | Add QSPI loader and UART recovery; verify image integrity checks and safe recovery from corrupted flash images. | Pending |
| 13 | Boot OpenSBI and lean Buildroot Linux; reach kernel entry in RTL and a repeatable serial shell on the board. | Pending |
| 14 | Implement a correct single-MAC DMA path and handle-based Linux driver; pass repeated bit-exact matrix jobs and error cases. | Pending |
| 15 | Measure a roofline for the 784→64→10 model at batch sizes 1 and 8, including DDR bandwidth, arithmetic intensity, copy time, and driver time. | Pending |
| 16 | Scale through 4×4 and at most 8×8 MAC tiles. Keep the largest tested size that meets timing and reaches at least 70% MAC utilization on batch 8. | Pending |
| 17 | Run the quantized classifier with weights uploaded once. Match CPU results and report batch throughput, single-image latency, DMA time, and driver time separately. | Pending |
| 18 | Publish reproducible builds, QSPI image, timing/utilization results, roofline, debug guide, and demo. Confirm power-on Linux boot and UART recovery. | Pending |

## Working rule

A failed checkpoint blocks new features until its cause has a small reproducer. If full Linux RTL simulation becomes too slow, use RTL for bounded boot milestones and the trace ring plus ILA for later board execution. If time runs short, finish the Linux shell and correct 4×4 DMA system before pursuing the 8×8 array or later optimizations. Record every such decision and its evidence here.

## Checkpoint record

Each completed checkpoint receives a dated record under `docs/checkpoints/` with the commit, commands run, observed results, open risks, and any change to the plan. Work on the next checkpoint starts after that record is reviewed.
