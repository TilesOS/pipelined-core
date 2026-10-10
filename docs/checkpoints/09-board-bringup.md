# Checkpoint 9 board bring-up

Status: checkpoint 9's functional board gate is complete on 2026-10-10.
The measured RTL is `7d224a7aaa56007d020cbc75e3879c9e9a00adf6`. BRAM mapping,
50 MHz routed setup/hold timing, timing coverage, first UART execution and
CPU RESET/retest pass. The CPU/cache slice allocation overage remains an
open area review for privilege/TLB integration. Checkpoint 10 remains a
separate branch.

The harness uses the checkpoint 8 PLL, MIG wrapper and physical pinout with
the actual checkpoint 9 CPU, L1 caches, fabric and clock crossing. A committed
8 KiB ROM image runs at reset PC zero; no DDR loader, OpenSBI or flash image is
needed. The program and linker are in tests/board/checkpoint9_smoke.S/.ld.
Regenerate with bash scripts/build_checkpoint9_rom.sh --update; without
--update the script checks that the committed ROM matches its source.

## Test and diagnostic contract

The ROM writes its phase to 0x10030000 and its result to 0x10030004. These are
test-only debug registers, not the checkpoint 10 peripheral ABI.

| Phase | Check |
|---|---|
| 1 | Cached word, byte and halfword access |
| 2 | Three dirty lines sharing one two-way D-cache set; eviction and reload |
| 3 | All eight words in 512 lines (16 KiB), FENCE.I clean, full data reload |
| 4 | Cached executable code, two FENCE.I rewrites and I-cache conflicts |
| 5 | Cached/pool boundary and DDR end; uncached data and executable rewrites |
| 6 | Cached LR/SC, AMOADD, conflicting-store reservation clearing; pool LR/SC |
| 7 | Traffic-counter checks and background DMA error check |
| 8 | Success marker 0xc900600d, followed by deliberate EBREAK halt |

The second AXI master continuously writes and verifies 128-bit words at
0x87ff8000, disjoint from CPU test locations. This is background test traffic,
not an accelerator or a bandwidth measurement. New writes stop when the CPU
halts; an admitted transaction drains. Failure stores 0xc9ba0000 OR phase and
halts with EBREAK. An unexpected CPU trap also halts and appears in the report.

UART emits a snapshot every approximately one second at 115200 baud, 8N1.
The C9SM v1 packet is five header bytes plus fourteen little-endian 32-bit
words: flags, phase, result, last retired PC, cause, tval, I misses, D misses,
D writebacks, I bypasses, D bypasses, DMA trips, DMA errors, core cycles.
Flag bits 0..3 mean calibrated, masters ready, CPU halted and passed.
The reporter starts before calibration and does not depend on CPU progress.
The legacy trace UART is not wired to the physical pin in this smoke harness;
the report retains the last retired PC and fault while stalled.

LED 0 indicates MIG calibration. LED 1 indicates success, LED 2 indicates a
halted failure, and LED 3 is the core heartbeat. A pass requires phase 8,
the success marker, the expected cause 3, nonzero DMA trips with no errors,
at least four I misses, 512 D misses/writebacks and both bypass paths used.

On Verilator 5.032 the full harness passes two unrelated clock ratios with
backpressure, a complete rerun after calibration loss, and a serial packet
check. The first normal run reports 5 I misses, 1,035 D misses, 521 writebacks,
zero DMA errors and the success marker. An injected DMA B error produces phase
7 failure, which the host decoder rejects. Board top lint is warning-free.
These counts and cycles are simulation evidence, not physical measurements.

The first board synthesis on 2026-10-08 reported 21,415 total LUTs, no block
RAM, and 12 DSPs. Cache lookup and maintenance had separate data read ports,
so the line stores mapped to LUT RAM. They now share one reset-free,
synchronous read port per way, with a separate write port and block RAM
inference requested. The CPU now shares one unsigned multiply product;
signed high halves use operand corrections. New physical resource counts
must be measured after resynthesis.
After these RTL changes on 2026-10-09, both cache unit-test seeds, the full
checkpoint 9 cached-CPU/Spike regression (including directed and four seeded
M-extension programs), and the complete board simulation/lint gate passed.

The operator's Vivado 2026.1 synthesized-design report on 2026-10-09 confirms
the new mapping: 16,403 total LUTs, 10,867 FFs, 16 RAMB36s, four RAMB18s and
four DSPs. Each cache uses eight RAMB36s plus two RAMB18s, nine BRAM36
equivalents. The CPU/cache hierarchy uses 8,851 LUTs, 4,956 FFs, 18 BRAM36
equivalents and four DSPs, within the 30-BRAM36/eight-DSP allocations.
The board clock port is E3/LVCMOS33. The console output, with host/path
metadata removed and trailing whitespace normalized, is retained in
[09-board-synthesis.txt](evidence/09-board-synthesis.txt). Placed slice use,
routed setup/hold/CDC/DRC and board execution are still pending; this is not
physical signoff.

The operator's routed timing summary on 2026-10-09 reports setup WNS
**+0.893 ns**, TNS **0**, and **0 failing setup endpoints**; hold WHS
**+0.031 ns**, THS **0**, and **0 failing hold endpoints**. Pulse-width slack
is **+0.206 ns** with no failures. Routed resource/clock/CDC/methodology/DRC
review and physical board execution remain pending.

The first routed resource report uses 5,411 total slices (34.14%), with
3,066 occupied slice sites in the CPU/cache hierarchy, 66 above its
3,000-slice allocation before TLBs. The core and UI periods are 20.000 ns and
12.308 ns. There are no methodology Critical warnings or DRC Errors in the
reported rule summaries, but the new RAM control and calibration-status
findings prevent accepting this netlist. The initial report excerpts, with
host/path metadata removed and trailing whitespace normalized, are in
[09-board-route-before-control-fix.txt](evidence/09-board-route-before-control-fix.txt).

- REQP-1839/1840 identify asynchronously reset `core_release[1]` driving cache
  RAM enables. RAM read/write controls, addresses and write data now pass
  through a clocked stage without asynchronous reset. Lookup and maintenance
  each wait one additional cycle for that stage. An admitted RAM write may
  drain across reset, while all valid/dirty metadata is discarded.
- CDC-10 identifies the UI reset/calibration expression feeding the UART
  status synchronizer. It is now registered on the MIG UI clock before the
  existing two core-clock synchronizer stages.
- Cache hit stores now use byte enables and replicated, rotated input bytes
  instead of a 256-bit read/modify/write network. New tests cover sparse
  relative strobes spanning words and all 32 line byte offsets, including
  writeback preservation. Both seeds pass 324 unit-test operations.

The full cache/CPU/Spike and board simulation/lint gates pass these changes.
At that point, new FPGA slice/timing measurements and diagnostic remediation
needed a fresh implementation, now recorded below. The compact helper
`python3 scripts/summarize_checkpoint9_reports.py` inventories report rule
counts and CDC source families without waiving any finding.

### Corrected route at source commit 7d224a7

The operator initially reopened an older implemented design after updating
the checkout. Its timing/resources were identical to the previous route and
it contained no `calib_ui_reg`. Explicitly resetting both `impl_1` and
`synth_1`, rebuilding synthesis, and checking for one `calib_ui_reg` confirmed
the current RTL before a new implementation. A checkout revision alone does
not identify a saved Vivado netlist.

The new route reports setup WNS **+1.310 ns**, hold WHS **+0.027 ns** and
pulse-width slack **+0.206 ns**, with zero failing endpoints and zero total
negative slack for all three checks. Core/UI/reference periods remain
20.000/12.308/5.000 ns. Total use is **5,387 slices (33.99%)**, 15,765 LUTs,
11,242 registers, 18 BRAM36 equivalents and four DSPs. The operator's
primitive-to-site query reports **3,161 CPU/cache occupied slice sites**.
These are operator-supplied measurements, not locally reproduced Vivado runs.

REQP-1839/1840 and CDC-10/13 are absent. Calibration status now has one
CDC-3 synchronized crossing. The complete helper inventory accounts for
all CDC summary counts, with no OTHER or incomplete-inventory category:

| Finding | Count | Source inventory and review |
|---|---:|---|
| CDC-1 Critical | 1,432 | FIFO payload RAM: 110 B, 998 R, 324 W sources. Registered cache controls remove the previous direct RAM-control endpoints. Payload remains stable until the read pointer returns through two source registers; destination consumption follows the synchronized write pointer and ready/valid handshake. |
| CDC-15 Warning | 381 | FIFO payload RAM: 26 AR, 26 AW, 322 R, 7 W sources. The same storage ownership and synchronized-pointer protocol applies. |
| CDC-6 Warning | 10 | Both Gray-pointer directions in all five FIFOs; registered pointers cross through two ASYNC_REG stages. The 12 ns datapath bound is below the fastest source period. |
| CDC-11 Critical | 6 | Registered link reset, including core_release and the five core-domain FIFO release chains. Assertion is asynchronous; release is synchronized locally. Ready/valid and master reset gating prevent handshakes during local reset. |
| CDC-3 Info | 4 | Three generated MIG crossings and one registered UART calibration-status crossing. |
| CDC-8 Warning | 2 | Generated MIG reset endpoints; the same IP configuration used in checkpoint 8. |

This is a manual protocol review of the reported source inventory and current
RTL, not a severity change or automatic CDC waiver. The timing coverage and
physical reset/retest results are recorded below. Methodology has no
Critical findings. Remaining methodology rule counts match the earlier
MIG/custom-FIFO findings; SYNTH-6/10 are optional RAM/DSP timing optimization
guidance, with routed timing passing. DRC reports only DPOP-1/2 (four each,
optional DSP output/multiplier pipeline stages) and the generated MIG clock
cascade REQP-1709 (one).

The CPU/cache slice allocation is exceeded by **161 sites (5.37%)**, before
TLBs. The RAM input registers add sequential logic and the placement count
increased even though total occupied slices fell by 24. The area reduction
hoped for from byte stores was not demonstrated. Review decision: proceed
with checkpoint 9 physical functional testing because the build fits the
device and meets timing; retain the 3,000-site allocation and an open area
review for privilege/TLB integration. Do not represent the CPU as within its
allocation or add accelerator lanes without reviewing the complete measured
design. Shared slice sites across hierarchies can also make per-block site
counts non-additive. The total board build has 10,463 unused slice sites;
that is current capacity, not a reservation for unimplemented features.

The operator subsequently completed bitstream generation and ran
`check_timing -verbose` on the routed `checkpoint9_board_top`. No-clock,
constant-clock, pulse-width-clock, unconstrained internal endpoints,
multiple clocks, generated-clock connectivity, combinational/latch loops,
and partial input/output delay checks all report zero. The only missing
external delays are `CPU_RESETN` and the five outputs `LED[0..3]` and
`UART_RXD_OUT`. These are an asynchronous button, human-visible status and
asynchronous serial output, with no synchronous external receiver clock
contract. No external I/O timing constraint is invented to silence these
messages. Bitstream generation completed and both physical runs below pass.

### First physical execution, 2026-10-10

The operator programmed the new bitstream over JTAG and reported the expected
LED states (calibration/success on, failure off, heartbeat blinking).
A five-second UART capture contains 305 bytes; the decoder finds a complete
61-byte report.
The decoder reports phase 8, result `0xc900600d`, halted/passed flags, and the
deliberate EBREAK at PC/tval `0x338`, cause 3. I/D misses are 5/1,035,
dirty writebacks 521, I/D bypasses 53,461/27, DMA trips 27,964 and DMA errors
zero. The reported CPU runtime is 935,711 cycles, 0.018714 s at 50 MHz;
this is a smoke-test duration, not a bandwidth or accelerator benchmark.
The supplied decoder output is retained in
[09-board-uart.txt](evidence/09-board-uart.txt). The raw first capture is
retained on the operator PC as `build/checkpoint9-board/uart-first.dat`;
it has not been transferred or independently decoded locally.

### CPU RESET/retest and board-gate acceptance, 2026-10-10

After pressing/releasing CPU RESET and waiting for the board to restart,
the operator captured another 305 bytes and ran the same decoder. The
second run passes with the same phase, result, EBREAK diagnostic and cache
counters. DMA trips are 28,218 with zero errors; runtime is 942,658 cycles,
0.018853 s at 50 MHz. The second raw capture remains on the operator PC as
`build/checkpoint9-board/uart-reset.dat`. Both operator-supplied decoder
outputs are preserved in [09-board-uart.txt](evidence/09-board-uart.txt).

The operator's SHA-256 for `checkpoint9_board_top.bit` is:

```text
9c946fe0656e3dc9cef0325b2b3828624e6e5633c747d5b77015add213ee8816
```

The reports apply to `checkpoint9_board_top`, `xc7a100tcsg324-1`, Vivado
2026.1 and source commit `7d224a7`. The accepted result is the ROM smoke
test with cached CPU and competing DMA plus reset/retest; it is not a
Linux/OpenSBI boot, flash boot or a throughput measurement. Physical results
are supplied by the operator, with raw captures and full Vivado reports
retained on that PC rather than reproduced on the Mac. The compact routed
evidence is in [09-board-route.txt](evidence/09-board-route.txt).
The [GitHub Actions run for the exact measured RTL](https://github.com/TilesOS/pipelined-core/actions/runs/37996434305)
completed successfully. The functional board gate is accepted with the
reviewed area overage and retained diagnostic severities described above.

The generated MIG XDC also tries to apply E3/LVCMOS25 to its scoped
`sys_clk_i`. A synthesis-inserted shared input buffer prevents that scoped
pin from resolving to the board port, producing two Netlist 29-160 warnings.
The top-level board XDC owns the actual E3/LVCMOS33 assignment. Both the
synthesis and implementation check scripts verify that assignment, and
the routed clock/timing coverage and physical calibration/reset retest pass.
These scoped-IP diagnostics are accepted for this board configuration.
Generated MIG files are not edited or their messages suppressed.

## Vivado and board procedure

1. Save the working checkpoint 8 project under a new name. The operator's
   project copy is /home/tyler/checkpoint9_board/checkpoint9_board.xpr.
   The repo is /home/tyler/Documents/pipelined-core on checkpoint9-caches.
2. Source scripts/checkpoint9_add_sources.tcl from that repo in the copied
   project's Tcl Console. It prepares the existing ddr_probe.bd wrapper,
   replaces copied RTL associations, adds the ROM, selects checkpoint9_board_top,
   and enables checkpoint 9's pin/CDC constraints. Simulation vendor stubs
   must never be added to Vivado.
   The CDC file is registered as a Tcl constraint file so its clock-object
   validation conditionals execute; managed XDC does not support `if`.
   Its implementation-only usage is set after the file type and verified.
   The first Tcl registration attempt ran during synthesis and failed because
   the out-of-context MIG was still a black box with no internal UI clock pin.
3. Run synthesis, then source scripts/checkpoint9_check_synth.tcl. Review
   block RAM inference and hierarchical utilization, including the CPU/cache
   allocation of 3,000 slices, 30 BRAM36 and 8 DSP with space for later TLBs.
   Total board utilization includes ROM, MIG, fabric and test traffic.
   After pulling changed RTL, close the open design and explicitly reset
   impl_1 and synth_1 before rebuilding. Confirm the new calibration source
   register exists in synthesis; do not rely only on the checkout revision.
4. Run implementation and source scripts/checkpoint9_check_impl.tcl. Review
   setup and hold timing, clocks, CDC, exceptions, methodology and DRC for
   this netlist. The core clock must be 50 MHz. Prior checkpoint 8 endpoint
   acceptance does not automatically cover new crossings.
5. Generate a bitstream and program SRAM over JTAG. Capture the report with
   python3 scripts/capture_checkpoint9.py /dev/ttyUSB1, substituting the real
   serial port, then run python3 scripts/decode_checkpoint9.py on the capture.
6. Press/release CPU RESET and obtain a second passing capture. Retain the
   raw captures, Vivado reports, exact source commit and bitstream identity.
   Record physical evidence before signing off the board gate.

Reports and captures default to ignored build/checkpoint9-board/. Preserve
accepted evidence in docs/checkpoints/evidence/ when closing the checkpoint.
