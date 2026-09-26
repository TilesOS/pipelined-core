# Checkpoint 7: AXI fabric, width bridge, and clock crossing

Status: complete in RTL simulation on 2026-09-26. Implementation commit: `a462b55`. This checkpoint establishes the bus subsystem; it does not claim DDR board bring-up or CPU cache integration.

## Delivered

- Four-master, two-slave AXI fabric with independent read and write arbitration, fixed downstream master IDs, one read and one write transaction in flight at the fabric boundary, round-robin grants at burst boundaries, and per-master response routing. DDR accepts aligned 128-bit INCR bursts of 1–16 beats. ROM/MMIO accepts single-beat accesses. Invalid regions, illegal sizes, and 4 KiB-crossing bursts return DECERR without reaching a slave.
- A 32-to-128-bit CPU width bridge for byte, halfword, and word requests, with byte-lane strobes, a narrow mode for side-effecting peripherals, held responses, and alignment errors. The peripheral adapter turns a narrow AXI access into exactly one byte-addressed device request.
- Five dual-clock Gray-pointer FIFOs for AW, W, AR, B, and R. Each synchronizes reset release locally. `axi_subsystem` gates the fabric on MIG calibration and exposes channel owner, activity, and FIFO-level debug probes. A calibration loss resets the link and aborts outstanding work; masters reissue after `masters_ready` returns.

## Evidence

`bash scripts/run_checkpoint7.sh` passed on OrbStack Ubuntu with Verilator 5.032. It builds without Verilator warnings and runs:

```text
PASS: 10 bridge operations, byte lanes, errors, response hold
PASS: seven narrow peripheral accesses, exact byte address and one device request each
PASS: 75 bus operations, clocks 5/7, reset after 1 beats, W FIFO full=1
PASS: 75 bus operations, clocks 3/11, reset after 7 beats, W FIFO full=1
PASS: 75 bus operations, clocks 11/3, reset after 15 beats, W FIFO full=1
PASS: 75 bus operations, clocks 4/13, reset after 4 beats, W FIFO full=1
PASS: 75 bus operations, clocks 13/4, reset after 11 beats, W FIFO full=1
```

Each bus run drives four concurrent masters through seeded slave backpressure. A byte-level memory scoreboard checks full read beats, including bytes masked off in previous writes. Monitors check AW/W/AR/B/R stability under backpressure, first-round grant order, bounded arbitration wait, simultaneous read/write activity, a full write FIFO, FIFO occupancy, response IDs, burst termination, decode faults, and recovery after calibration loss. The CI workflow runs the same script.

## Next integration

Checkpoint 8 connects the MIG IP and measures actual 128-bit DDR transfers, timing, and bandwidth on the Nexys A7. Checkpoint 9 connects the CPU through caches and the width bridge. Checkpoint 10 supplies the address-decoded devices behind the peripheral adapter. The standalone simulation does not measure FPGA resource use, post-route timing, or real DDR calibration.
