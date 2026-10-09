# Checkpoint 9 board bring-up

Status: board harness prepared and simulated on 2026-10-08. Physical FPGA
resources, timing and execution remain unmeasured until the operator records
the Vivado reports and UART captures. Checkpoint 10 remains a separate branch.

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
The new FPGA slice count, setup/hold timing and diagnostic remediation remain
unmeasured until the next implementation. The compact helper
`python3 scripts/summarize_checkpoint9_reports.py` inventories report rule
counts and CDC source families without waiving any finding.

The generated MIG XDC also tries to apply E3/LVCMOS25 to its scoped
`sys_clk_i`. A synthesis-inserted shared input buffer prevents that scoped
pin from resolving to the board port, producing two Netlist 29-160 warnings.
The top-level board XDC owns the actual E3/LVCMOS33 assignment. The synthesis
check verifies that assignment; the routed I/O and clock reports still need
review before accepting those generated-IP diagnostics. Generated MIG files
are not edited or their messages suppressed.

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
