# Checkpoint 10 board bring-up

Status: the first compact-ROM route fits at 84/135 block RAM tiles but fails
50 MHz setup timing (WNS -9.369 ns) and exposes trace RAM asynchronous-control
warnings. PMP/trace RTL fixes require fresh synthesis and routing before
bitstream generation. Physical serial execution remains pending.
The operator confirmed checkpoint 9's board
signoff and Nexys A7 cable availability on 2026-10-11. The Ubuntu PC runs
Vivado 2026.1. Preserve `/home/tyler/checkpoint9_board` and its accepted
bitstream; use a separate `/home/tyler/checkpoint10_board` project.

The source branch is `checkpoint10-peripherals`, including approved
checkpoint 9 FPGA fixes through merge `f523289`. The new target is
`checkpoint10_board_top`, using the same PLL, MIG wrapper, DDR pinout and
late implementation-only CDC constraints. It enables the actual privilege,
PMP, caches and standard devices; no simulation vendor model enters Vivado.

## Image and execution contract

The board proof embeds a generated ROM with pinned OpenSBI v1.7 and a small
S-mode payload. ROM storage contains firmware followed immediately by payload;
the loader supplies zeroes for their reserved DDR gap. After calibration,
master 2 writes each 128-bit image word
to DDR and reads it back. The CPU and both caches stay reset until the entire
image is verified. A failed AXI response, wrong response ID, missing RLAST,
data mismatch or timeout blocks CPU release and lights LED 2. Reset or
calibration loss resets transport/CPU/cache/loader state and restarts copying.

The image starts at `0x80000000`; the S payload runs at `0x80040000`, and
OpenSBI relocates its embedded FDT to `0x80060000`. The firmware reservation
and image padding end at `0x80040000`. These are bounded board-proof addresses,
not the production Linux image layout. This is a test-image ROM loader,
not checkpoint 12's QSPI loader or UART recovery implementation.

The payload checks DTB/hart identity, SBI BASE, MTIP-to-STIP timer delivery,
S trap return and resident firmware PMP protection, then emits:

```text
CHECKPOINT10 SBI TIMER/PMP PASS
CHECKPOINT10 UART RX READY: send K
```

The capture tool sends one ASCII `K` after seeing READY. The payload checks
SEIP, claims UART source 1 in the S PLIC context, reads the physical UART RX
byte, disables its receive interrupt, completes the PLIC gateway, returns
with SRET, and emits `CHECKPOINT10 UART RX/PLIC PASS`. Only then does the
retirement success signature light LED 3. The terminal is 115200 baud, 8N1,
without hardware flow control. UART TX is D4 and RX is C4.

| LED | Meaning |
|---|---|
| 0 | Calibrated fabric/CDC masters ready |
| 1 | Entire image written and read back; CPU released |
| 2 | Loader, payload or fatal CPU failure; must remain off |
| 3 | S-mode timer/PMP and physical UART/PLIC payload passed |

BTNC (N17) requests diagnostic ownership. A 10 ms debounce halts the CPU;
ownership changes only after the console FIFO and serializer drain and stay
idle for 64 core clocks. The independent trace engine then sends its usual
`TRCE` packet. The UART stays in diagnostic mode, with the CPU halted, until
CPU RESET. This preserves the last stop bit and prevents console interleaving.
The board top also marks last retired PC/cause/tval for ILA access. A UART
break or firmware that never drains TX prevents diagnostic pin handover;
the last-PC probes remain available.

## Simulation evidence

On the managed Debian 13 cloud workspace with Verilator 5.032, GCC 14.2
and DTC 1.7.2, the loader failure/watchdog/reset tests, UART owner tests and
warning-free board top lint pass. The full board execution boundary passes
core/MIG half-periods 5/7 and 3/11 with seeded backpressure and nonzero initial
DDR. Both runs interrupt copying with calibration loss, verify the image,
execute real OpenSBI and the S timer/PMP plus physical-pin UART/PLIC path,
reset/reload/retest, and receive a complete 256-record shared-pin trace packet.
The existing privilege, peripheral/MMIO, generic OpenSBI and checkpoint 9
board regressions pass. The final test image is 262,816 bytes: 133,884-byte
firmware, padding to the 256 KiB reservation, a 672-byte payload and alignment
padding. The compact ROM stores 134,560 bytes / 8,410 words. Its generated
header separately describes the stored words and full DDR image words.
Host packing/capture and Tcl project-preservation guards also pass.
Saved compact results are in [10-board-simulation.txt](evidence/10-board-simulation.txt).
These results establish the prepared target in simulation. Physical synthesis
resource checks now pass; routed timing and physical execution remain pending.

## First physical synthesis and ROM capacity fix

The operator's Vivado 2026.1 reports for `checkpoint10_board_top` on
`xc7a100tcsg324-1` show 22,624 LUTs (35.68%), 12,725 registers (10.04%),
five total DSPs, and 144 RAMB36 tiles (106.67%). The CPU uses four DSPs;
both caches use eight RAMB36s each. The original padded image ROM consumes
128 RAMB36s, so this netlist cannot be placed on the 135-tile device.
The exact source manifest was not supplied with the reports.
The operator's original reports are preserved as
[utilization](evidence/10-first-synthesis/synthesis_utilization.rpt) and
[hierarchy](evidence/10-first-synthesis/synthesis_hierarchy.rpt).

The 16,426-word DDR image slightly exceeds a 16,384-word ROM depth and
causes inefficient memory allocation. Compacting the stored image to
8,410 words removes the large zero gap from ROM storage. The loader still
writes and reads back every DDR word, including that gap, before releasing
the CPU. Firmware/payload addresses and the DDR image contract are unchanged.
The synchronous ROM read remains reset-free.
The synthesis checker now rejects total block RAM use above 135 tiles.

The operator's fresh synthesis report and checker output on 2026-10-11 confirm
**84/135 block RAM tiles (62.22%)**, down from 144. The ROM uses 64 RAM
primitives; both caches infer block RAM (ten primitives each). Total use is
82 RAMB36s plus four RAMB18s, 22,485 LUTs (35.47%), 12,268 registers (9.68%)
and five DSPs; the CPU still uses four DSPs within its eight-DSP allocation.
The clock pin check passes E3/LVCMOS33. The two scoped MIG Netlist 29-160
warnings remain and require routed I/O review. The later implementation archive
supplies the clean `c444cb6` source/image manifest for this build. See the saved
[utilization](evidence/10-compact-synthesis/synthesis_utilization.rpt) and
[checker console](evidence/10-compact-synthesis/synthesis_console.txt).
These resource checks permit proceeding to implementation; timing, actual
occupied slices, CDC/DRC and board execution still require new evidence.

## First routed implementation and PMP/trace fixes

The operator's 2026-10-11 archive records clean source
`c444cb69287f3291fe1f7fa7391896e271e735f7`, Vivado 2026.1 and the pinned
OpenSBI revision above. The Ubuntu image contains 133,892 firmware bytes,
672 payload bytes and 262,816 logical DDR bytes; its compact ROM stores
134,576 bytes / 8,411 words. Compiler-dependent firmware size differs from
the cloud simulation image. Exact hashes are retained in the
[image manifest](evidence/10-first-route/image-manifest.json).

The fully routed design uses 21,497 LUTs, 11,932 registers, 7,089 total
occupied slices, 84 BRAM tiles and five DSPs. Setup fails with **WNS -9.369 ns,
TNS -6215.763 ns and 834 failing endpoints**. Hold (WHS +0.024 ns) and pulse
width (WPWS +0.206 ns) pass. The worst path runs from PMP address entry 4
to the memory-stage trap value: 29.195 ns data delay, 49 logic levels and
20 CARRY4s. The trace RAM additionally produces REQP-1839 warnings for
asynchronous reset-driven controls; the report is capped at 20 violations.
These are blockers, despite routing completing successfully.

The PMP fix derives each NAPOT mask with constant-position prefix reductions,
matches addresses with masked equality, and selects the first overlapping
entry from parallel results. It removes the serial trailing-one counter,
variable shift and upper-bound addition. Data-check inputs now decode
independently of instruction permission, removing two permission networks
in series while retaining instruction-fault priority in execute. Empty or
reversed TOR regions have no overlap. An independent numeric interval model
tests the real checker across NAPOT sizes, boundaries, priority and M/S/U modes.

The trace fix registers RAM write/read enables and addresses without reset,
leaves RAM contents/read output reset-free, and adds one read wait cycle.
Reset invalidates the trace metadata. The packet format and oldest-first
record order are unchanged. The final privilege/PMP gate passes 106,808
interval-reference checks and all three clock ratios, including precise
LR/SC/AMO protection faults. CPU/Spike and trace-wrap checks pass. The full
board gate passes both clock ratios, calibration-loss restart, OpenSBI/S
timer/PMP, UART/PLIC, CPU reset/reload and complete 256-record trace dumps.
See [remediation simulation evidence](evidence/10-timing-fix-simulation.txt).
Fresh Vivado reports must demonstrate improved
setup timing, continued BRAM inference and no trace REQP-1839 warnings;
simulation cannot establish those physical results.

The supplied I/O report maps the board clock/reset/UART/button/LED pins as
specified. Timing coverage reports no missing clocks, unconstrained internal
endpoints or loops; absent port delays are the asynchronous reset/button/RX
inputs and LED/TX outputs. CDC detail rows classify the FIFO payload storage,
Gray pointers, registered link reset and generated MIG endpoints in the
preserved checkpoint 9 inventory. The new route still needs complete
timing/CDC/DRC review and a CPU/cache occupied-site query. Retained
[summary](evidence/10-first-route/summary.txt),
[worst path](evidence/10-first-route/worst-path.txt), utilization, hierarchy,
DRC, timing-coverage and console reports document this failed route.

## Separate source and Vivado projects

In an Ubuntu terminal, create a dedicated source checkout. The clone command
refuses to overwrite an existing directory.

```sh
git clone --branch checkpoint10-peripherals --single-branch \
    https://github.com/TilesOS/pipelined-core.git /home/tyler/checkpoint10_src
cd /home/tyler/checkpoint10_src
sudo apt-get update
sudo apt-get install -y gcc-riscv64-unknown-elf gcc-riscv64-linux-gnu \
    device-tree-compiler verilator
bash scripts/build_checkpoint10_board_image.sh
bash scripts/run_checkpoint10_board.sh
```

The image builder writes `build/checkpoint10-board/checkpoint10_image.mem`,
an absolute-path include header, and `image-manifest.json` with source/firmware
revisions, compact-ROM/full-DDR sizes, layout and SHA-256 hashes. Rebuild the image after moving the checkout
or changing firmware/payload; regenerate Vivado runs after changing the image.
It is deliberately a build artifact, rather than a checked-in firmware blob.

The payload uses explicit zero padding before its `fail` instruction label.
Binutils 2.40 otherwise skips the required two-byte padding under `norvc`,
producing the rejected address `0x8004026e`. With explicit padding, binutils
2.40 and 2.44 both place `fail` at `0x80040270`, pass all instruction-label
alignment checks, and produce identical payload bytes for both build variants.

Open the proven checkpoint 9 project in Vivado and use **File → Project →
Save As** to create `/home/tyler/checkpoint10_board/checkpoint10_board.xpr`.
Copy/import project sources, especially `ddr_probe.bd`, into the new project.
The source-install script refuses a checkpoint 9 project directory or a BD
still pointing outside the new project, because preparing the BD regenerates
its wrapper. Keep the checkpoint 9 project closed after making the copy.

In the copied project's Tcl Console:

```tcl
source /home/tyler/checkpoint10_src/scripts/checkpoint10_add_sources.tcl
catch {close_design}
reset_run impl_1
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
source /home/tyler/checkpoint10_src/scripts/checkpoint10_check_synth.tcl
```

Review the synthesis output before routing. Both caches and the test-image
ROM must infer block RAM. The CPU multiplier allocation remains eight DSPs;
measure total usage including UART/PLIC/PMP and the temporary image ROM.
Checkpoint 9's CPU/cache slice overage remains an area review item. Its
previous resource/timing result does not establish this new target's result.
The script's hierarchy is `board/system/system/cpu`, with loader ROM under
`board/loader`. The implementation checker writes `cpu_cache_area.txt` with
unique CPU/cache occupied slice sites and the overage against 3,000 sites.
Never reopen a copied old run and treat it as a new build.

After synthesis review:

```tcl
launch_runs impl_1 -to_step route_design -jobs 4
wait_on_run impl_1
source /home/tyler/checkpoint10_src/scripts/checkpoint10_check_impl.tcl
```

Review 50 MHz setup/hold/pulse-width timing, BRAM controls, new RX/button CDC,
constraint coverage, methodology and DRC. The independent MIG UI clock remains
approximately 81.25 MHz. Existing FIFO/MIG findings retain their original
severities and need a source inventory for this netlist; do not suppress new
diagnostics. External reset/buttons/UART have asynchronous I/O contracts.
Full reports go to `build/checkpoint10-board/vivado-reports`. The checkpoint 9
report summarizer can inventory this directory when passed its explicit path.

## Programming and acceptance evidence

After route review, generate the bitstream and program FPGA SRAM over JTAG:

```tcl
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
```

Use Hardware Manager to program `checkpoint10_board_top.bit`. Find the same
USB serial device used for checkpoint 9, close competing terminal programs,
then start capture **before** pressing/releasing CPU RESET:

```sh
cd /home/tyler/checkpoint10_src
python3 scripts/capture_checkpoint10.py /dev/ttyUSB1 \
    --output build/checkpoint10-board/uart-first.dat
python3 scripts/capture_checkpoint10.py /dev/ttyUSB1 \
    --output build/checkpoint10-board/uart-reset.dat
```

Press/release CPU RESET when each capture says it is ready. Both captures
must report PASS, and LEDs 0/1/3 must be on with LED 2 off. The test is a
one-time serial sequence per reset; opening capture after boot misses the
banner. Preserve raw bytes, rather than only a terminal screenshot.

For diagnostics, after a passing run:

```sh
python3 scripts/capture_checkpoint10.py /dev/ttyUSB1 --trace --seconds 5 \
    --output build/checkpoint10-board/trace.dat
python3 scripts/decode_trace.py build/checkpoint10-board/trace.dat
```

Press BTNC after the capture starts. A full oldest-first trace packet must
decode, including S-mode retirement, and CPU RESET must restore console boot.
Record the exact source commit, image manifest and bitstream SHA-256 with the
synthesis/routed reports and both captures. The physical board gate remains
pending until those measurements and repeatable serial results are reviewed.
Sv32, Linux boot and production QSPI loading remain later checkpoints.
