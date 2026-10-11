# Checkpoint 10 board bring-up

Status: checkpoint 10's functional board gate is complete on 2026-10-11.
First boot, CPU RESET retest, complete S-mode trace and post-trace reset recovery
pass; the operator reports LEDs 0, 1 and 3 on. See
[physical acceptance](#physical-board-acceptance-2026-10-11).
The fifth route at clean implementation source `5b74119`, retaining
`74d26b9` synthesis/image, passes 50 MHz setup/hold/pulse timing
(+0.308/+0.017/+0.206 ns). The targeted tag-RAM power-gating exclusion clears
REQP-1839/1840; both tag enables now have only their registered RTL startpoint.
FDRE CPU reset and 84/135 block RAM tiles are retained.
CPU/cache area is 4,710/3,000 sites; that area review remains open.
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
resource checks and the fifth route pass timing and RAM-control review as
recorded below; subsequent physical execution passes as recorded below.

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

## Second route and registered CPU release

The operator's second archive identifies clean source
`704f4a8f88ba94f4e8f09d255f95a000212c646f`. Its firmware/payload/ROM and DDR
image hashes match the first route. Setup WNS is **+0.368 ns**, hold WHS
**+0.016 ns**, and pulse-width slack **+0.206 ns**, with zero failing endpoints
or negative slack totals. The worst setup path is now execute instruction
bit 1 to the I-cache state: 19.445 ns data delay and 26 logic levels.
REQP-1839/1840 and report-limit warnings are absent; trace still infers two
RAMB36s. The image ROM uses 64 RAMB36s, each cache ten RAM primitives,
and the CPU four DSPs. Retained reports are in
[10-second-route](evidence/10-second-route/summary.txt).

Total routed use is 22,646 LUTs, 12,146 registers, **7,261 occupied slices**,
84 BRAM tiles (82 RAMB36 plus four RAMB18) and five DSPs. The unique CPU/cache
site query reports **4,749 slices**, **1,749 above the 3,000 allocation (58.3%)**.
This includes the trace hardware and is not additive with other hierarchy
site counts. The full device fits, with 8,589 unused slice sites, but the
original CPU/cache allocation remains exceeded. Keep the area review open
for privilege/TLB integration and before adding accelerator lanes; these
measurements do not establish capacity for unimplemented features.

All 55 assigned user port pins/directions/standards match the previous route,
including the scoped MIG DDR standards and E3 board clock. Timing coverage
still has no missing clocks, unconstrained internal endpoints or loops;
the asynchronous reset/button/RX and LED/TX port contracts are unchanged.
CDC source detail accounts for the complete summary: CDC-1 Critical 1,418
(95 B/999 R/324 W FIFO payload sources), CDC-15 Warning 381 (26 AR/26 AW/
322 R/7 W), CDC-6 Warning 10 (Gray pointers), CDC-11 Critical 6 (registered
link reset), CDC-3 Info 3 and CDC-8 Warning 2 (generated MIG). The existing
stable-payload/ownership, synchronized-pointer and local reset-release
review applies; no severities are changed. New UART RX and physical button
inputs use two ASYNC_REG stages; report_cdc skips ports without input delays.
DRC retains optional CPU/UART DSP pipeline guidance and the generated MIG
clock cascade warning. The UART timeout DSP has asynchronous register inputs
(DPIR-1); RAM/DSP methodology guidance remains, with routed timing passing.

The additional LUTAR-1 endpoint is `board/loader/cpu_i_1` driving the cache
bypass bridge asynchronous reset pins. CPU release previously combined
`masters_ready` with a combinational completion/error decode of loader state.
Decode pulses must not release/reset CPU/cache state. The fix adds opt-in
`REGISTER_CPU_RESET` to `checkpoint9_top`, enabled by `checkpoint10_top`:
a core-clock flip-flop samples `cpu_run`, resets asynchronously when locally
synchronized `masters_ready` falls, and drives CPU/cache reset directly.
Normal release waits one core edge. Legacy checkpoint 9 keeps its previous
default reset behavior and its proven checkout/bitstream remain available.

A directed test injects subcycle completion/run pulses, checks actual CPU
reset input stability, and verifies real withdrawal/calibration loss and
recovery. A negative control using the old combinational path fails on the
false completion pulse. The final privilege/PMP, legacy checkpoint 9 board,
and both full checkpoint 10 board clock-ratio gates pass, including reset/
reload and complete 256-record trace dumps. See
[registered-release simulation evidence](evidence/10-cpu-reset-simulation.txt).
Fresh routing must confirm that the loader-driven LUTAR-1 finding
is removed and timing/BRAM inference still pass. Both Vivado checkers inventory
the `cpu_reset_n_reg` primitives and reject a netlist without them, guarding
against accidentally reopening the previous implemented design. The separate generated MIG
LUTAR-1 endpoint remains part of the preserved IP reset inventory. The timing
pass at `704f4a8` does not establish timing for the registered-release change.

## Third route and clocked reset assertion

The operator's `checkpoint10_reports_resetfix.tar` identifies clean source
`08058590064e4925fa65265aa5ab7a197904f3fb`. Image hashes match the preceding
routes. Routed setup WNS is **+0.392 ns**, hold WHS **+0.030 ns**, and pulse
width slack **+0.206 ns**, with no failing endpoints or negative slack totals.
The worst setup path is execute instruction bit 0 to I-cache state bit 3:
19.275 ns data delay and 26 logic levels. Total use is 22,635 LUTs, 12,147
registers, 7,244 occupied slices, 84 BRAM tiles and five DSPs. ROM/cache/trace
mapping is retained: 64 ROM RAMB36s, eight RAMB36s plus two RAMB18s per cache,
and two trace RAMB36s. The CPU still uses four DSPs within its allocation.
Unique CPU/cache use is **4,813 sites**, **1,813 (60.4%) above allocation**.
The area review remains open. See [third-route evidence](evidence/10-third-route/summary.txt).

Both synthesis and route inventories confirm
`board/system/system/registered_cpu_reset.cpu_reset_n_reg FDCE`. The custom
loader LUTAR-1 has disappeared; the sole remaining LUTAR-1 is generated MIG.
However, two new **REQP-1840** warnings identify that FDCE driving
`icache/tags0_reg/ENARDEN` and `icache/tags1_reg/ENARDEN` through inferred
`cooolgate_en` nets. Vivado reports that asynchronous assertion can corrupt
RAM contents/read values outside the normal timing analysis. A passing timing
summary does not resolve those warnings; this route is not ready for programming.

The follow-up changes only checkpoint 10's opt-in reset stage to
`always_ff @(posedge core_clk) cpu_reset_n <= masters_ready && cpu_run`.
Both assertion and release are clocked; no asynchronous set/reset remains on
the register that Vivado can use for RAM enables. The PLL core clock is
independent of DDR calibration. Fabric/FIFO reset still aborts transport
asynchronously on link loss. The master-ready release chain holds low across
core edges, so CPU reset is sampled low before recovery; cache metadata is
discarded before image reload and CPU restart. Legacy checkpoint 9 retains
its default reset path. The directed test now checks between-edge master loss
as well as loader decode pulses and real calibration recovery. An `0805859`
negative control fails this new check, demonstrating the asynchronous reset
change at the actual CPU boundary. Full board and privilege/legacy gates are
recorded in [clocked-reset simulation evidence](evidence/10-clocked-reset-simulation.txt).

The complete CDC inventory retains the same rule totals and source families:
CDC-1 Critical 1,418 (35 B/1,059 R/324 W FIFO payloads), CDC-15 Warning 381,
CDC-6 Warning 10, CDC-11 Critical 6, and generated MIG CDC-3 Info 3/CDC-8
Warning 2. Payload endpoint allocation shifts between B and R with synthesis,
but no new source family appears. The existing ownership/Gray-pointer/reset
review applies with severities preserved. All 55 user pin assignments and
reported timing exceptions match the second route. Missing port delays remain
the asynchronous input and LED/UART output contracts; there are no missing
clocks, unconstrained internal endpoints or loops. Other DRC/methodology
inventory is unchanged; trace REQP-1839 remains absent.

Both Vivado checkers now require the CPU reset register to be **FDRE** and
reject the previous FDCE netlist. Rerun synthesis and routing, then review the
fresh reports for no custom RAM asynchronous-control warnings, continued
timing/BRAM mapping, and unchanged I/O/CDC contracts. The measured timing at
`0805859` applies to that source, not this subsequent clocked-assertion change.

## Fourth route and tag RAM power-gating exclusion

The operator's `checkpoint10_reports_clockreset.tar` identifies clean source
`74d26b9a0e0abac3d3b7931a72393bc289b9bfdc`. Firmware/payload/ROM/image hashes
match all preceding routes. Setup WNS is **+0.127 ns**, hold WHS **+0.021 ns**,
and pulse-width slack **+0.206 ns**, with no failing endpoints. Worst setup
is execute instruction bit 1 to I-cache state bit 3, with 19.608 ns data delay
and 25 logic levels. Total use is 22,634 LUTs, 12,147 registers, **6,878 slices**,
84 BRAM tiles and five DSPs. ROM/cache/trace mapping and four CPU DSPs are
retained. CPU/cache occupies **4,507 sites**, **1,507 (50.2%) above allocation**;
the area review remains open. See [fourth-route evidence](evidence/10-fourth-route/summary.txt).

Both synthesis and route inventories now report one FDRE CPU reset register.
The loader LUTAR-1 remains cleared; the sole LUTAR-1 is generated MIG. However,
the two I-cache tag ENARDEN REQP-1840 warnings now identify
`board/system/system/bus/core_release_reg[1]` as their asynchronous driver.
The clocked CPU reset fix did not clear the RAM control issue.

The operator compared `all_fanin -flat -startpoints_only` for both tag RAM
ENARDEN pins in synthesis and implementation. Synthesis has only
`icache/ram_read_enable_q_reg/C`, the intended reset-free clocked enable.
Implementation adds loader state, I-cache state, CPU reset, and asynchronous
master-release startpoints through `cooolgate_en` nets. This confirms the
unsafe extra gating is introduced after synthesis. Retained
[fan-in comparison](evidence/10-fourth-route/tag-enable-fanin.txt) records the
reported endpoint lists. The fabric's asynchronous abort/release chain must
remain intact; further upstream reset changes would not address this gating.

The implementation-only `checkpoint10_cdc.xdc` now selects exactly
`icache/tags0_reg` and `icache/tags1_reg` RAMB18 primitives and applies
`set_power_opt -exclude_cells` to them. This command excludes selected BRAMs
from the intelligent enable gating performed by default `opt_design` as well
as `power_opt_design`; other cell optimizations continue. The selector rejects
a missing/partial pair. Clock roots, both 12 ns CDC bounds, pins, reset RTL,
firmware, and diagnostic severities are unchanged. Vivado command help
documents this per-cell exclusion; see the pinned
[opt_design](https://github.com/Gladtbam/vivado-completion/blob/1224c83da6ad637d162188741cea26070bab4581/data/commands/opt_design/en.md)
and [set_power_opt](https://github.com/Gladtbam/vivado-completion/blob/1224c83da6ad637d162188741cea26070bab4581/data/commands/set_power_opt/en.md)
help snapshots. Actual effect still requires new Vivado evidence.

The implementation checker now saves the current Git source identity in
`implementation_source.txt`, plus `power_opt.rpt` and `tag_ram_controls.txt`;
it rejects any remaining REQP-1839/1840 detail findings
after writing timing/CDC/DRC reports. Tcl fixture checks select only the two
I-cache RAMs, reject zero/one match, preserve both 12 ns bounds, accept the
second-route DRC inventory, and reject the first/fourth-route RAM warnings.
The previous two-ratio board and privilege/legacy simulation results apply
to the unchanged RTL. See [constraint/guard validation](evidence/10-tag-ram-power-gating.txt).

All 55 user pin assignments and reported timing exceptions match the third
route. The complete CDC inventory has unchanged totals and source families:
CDC-1 Critical 1,418 (175 B/919 R/324 W FIFO payloads), CDC-15 Warning 381,
CDC-6 Warning 10, CDC-11 Critical 6, and generated MIG CDC-3 Info 3/CDC-8
Warning 2. Inherited methodology/DSP/MIG guidance and asynchronous external
port contracts are retained. There are no missing clocks, unconstrained
internal endpoints or loops. No constraint or severity waiver is added.

For this constraint-only update, pull the branch and retain the existing
firmware/ROM and `image-manifest.json`. The image manifest records the
unchanged `74d26b9` synthesis/image source, while `implementation_source.txt`
records the new constraint/checker commit and dirty status. Keep the existing
`synth_1` result, close the open design, reset **only `impl_1`**, rerun through
`route_design`, and source the implementation checker. The existing project
already reads this Tcl constraint file as implementation-only/LATE before
optimization, as confirmed by the operator's synthesis inspection transcript.
Review new timing, the tag-enable fan-in, and DRC before generating a bitstream.

## Fifth route: RAM controls cleared

The operator's `checkpoint10_reports_tagpower.tar` records clean implementation
source `5b74119793ba0520a208ee115d8fa0bf0820006e`. The retained synthesis reports
and `74d26b9` image manifest match the fourth route exactly. The constraint-only
reroute passes setup **+0.308 ns**, hold **+0.017 ns**, and pulse width
**+0.206 ns**, with zero failing endpoints or negative totals. The worst setup
path runs from execute instruction bit 0 to I-cache state bit 0: 19.360 ns
data delay, 26 logic levels and eight CARRY4s. See the
[fifth-route review](evidence/10-fifth-route/review.txt) and
[summary](evidence/10-fifth-route/summary.txt).

Both I-cache tag ENARDEN pins now have only
`icache/ram_read_enable_q_reg/C` as their fan-in startpoint. The power report
lists the two RAMs under user-gated BRAMs with the registered RTL read/write
controls. **REQP-1839/1840 are absent**, and CPU reset remains FDRE. The targeted
exclusion resolves the implementation-added asynchronous gating. Other
optimizations remain active; no timing or severity waiver was introduced.
Retained [tag controls](evidence/10-fifth-route/tag_ram_controls.txt),
[BRAM power-report excerpt](evidence/10-fifth-route/power-opt-bram.txt) and
[DRC](evidence/10-fifth-route/drc.rpt) document the result.

Routed use is 22,667 LUTs, 12,147 registers, **7,334 total occupied slices**,
84 BRAM tiles and five DSPs. ROM/cache/trace mapping remains unchanged, with
four CPU DSPs. Unique CPU/cache use is **4,710 sites**, **1,710 (57.0%) above
the unchanged 3,000 allocation**. The device fits; keep the area review open
for Sv32 integration and before adding accelerator lanes.

All 55 assigned user pins/directions/standards and timing exceptions match
the fourth route. Timing coverage has no missing clocks, unconstrained internal
endpoints or loops. The complete CDC inventory retains the same totals and
source families: CDC-1 Critical 1,418 (111 B/983 R/324 W FIFO payload sources),
CDC-15 Warning 381 (26 AR/26 AW/322 R/7 W), CDC-6 Warning 10 (Gray pointers),
CDC-11 Critical 6 (registered link reset), and generated MIG CDC-3 Info 3/
CDC-8 Warning 2. No additional source family appears. The existing stable
payload/ownership, synchronized-pointer, 12 ns bounds and local reset-release
review applies; severities are preserved. Asynchronous external port contracts
and remaining DSP/MIG/methodology diagnostics are unchanged. The sole LUTAR-1
remains generated MIG reset logic.

This review permitted generating a bitstream from the existing routed design.
Keep the operator's current source/image/synthesis/implementation together;
the evidence-only follow-up commit requires no rebuild or reroute. Physical
UART/LED/reset/trace acceptance subsequently passes below. The unchanged RTL
retains the privilege, legacy board and two-ratio full board simulation evidence.

## Physical board acceptance, 2026-10-11

The operator supplied `checkpoint10_board_evidence.tar` after programming the
Nexys A7-100T. All included Vivado reports and the image manifest byte-match
the reviewed fifth route. Implementation source remains clean `5b74119`, with
clean `74d26b9` synthesis/image. The operator-recorded bitstream SHA-256 is
`720f04fe02beef8279393162707290f69e58833f300c366c812cb4dbaa6aedf4`.
The archive contains the hash record rather than the bitstream binary; the
hash was not independently recomputed. See the retained
[acceptance review](evidence/10-board-acceptance/review.txt).

All three raw boot captures pass `capture_checkpoint10.py --verify`:
[first boot](evidence/10-board-acceptance/uart-first.dat),
[CPU RESET retest](evidence/10-board-acceptance/uart-reset.dat) and
[post-trace reset recovery](evidence/10-board-acceptance/uart-after-trace.dat).
Each is 2,598 bytes, and all three are byte-identical. They contain the ordered
OpenSBI v1.7 banner, SBI timer/PMP PASS, UART RX READY and UART RX/PLIC PASS.
The console reports one hart, eight PMP entries, the 1 MHz timer, uart8250,
and S-mode entry at `0x80040000` with FDT `0x80060000`. A readable
[console copy](evidence/10-board-acceptance/uart-first.txt) accompanies the raw bytes.
The operator reports LEDs **0, 1 and 3 on**, matching the expected pass on-set.

The [raw trace](evidence/10-board-acceptance/trace.dat) is exactly 4,358 bytes:
one `TRCE` header and 256 complete records, with no leading/trailing bytes.
The [decoded records](evidence/10-board-acceptance/trace-decoded.txt) all show
S-mode retirement (`priv=1`) at `0x8004014c`, instruction `0x0000006f`, with
zero cause/tval. This is the payload's post-success self-loop; its instruction
matches the hash-identical payload binary. Earlier interrupt/trap records
have wrapped out, while the serial milestones establish the timer/PMP and
physical UART RX/PLIC checks. Reset after diagnostic ownership restores the
same complete console sequence.

The functional board gate is complete, with the 50 MHz timing/resource and
RAM/CDC/DRC review retained. Raw captures, source/image identity, operator LED
report and checksums are saved under
[10-board-acceptance](evidence/10-board-acceptance/review.txt).
CPU/cache allocation remains exceeded by 1,710 slice sites (57.0%); retain that
area review for Sv32 and accelerator growth. Checkpoint 9's proven project and
bitstream remain separate. Sv32, production QSPI loading and Linux boot are
later checkpoints.

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
catch {close_design}
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
set checkpoint10_bitstream [file join [get_property DIRECTORY [get_runs impl_1]] checkpoint10_board_top.bit]
if {![file exists $checkpoint10_bitstream]} {error "checkpoint 10 bitstream was not generated; inspect impl_1 status"}
puts "Checkpoint 10 bitstream: $checkpoint10_bitstream"
set checkpoint10_hash_file [open /home/tyler/checkpoint10_src/build/checkpoint10-board/bitstream.sha256 w]
puts $checkpoint10_hash_file [exec sha256sum $checkpoint10_bitstream]
close $checkpoint10_hash_file
```

Use Hardware Manager to program the exact path printed by Vivado. Querying
`impl_1`'s directory avoids assuming a run-folder name after copying a project.
The commands also save its SHA-256 in the source checkout's evidence directory.
Find the same
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
decode, including S-mode retirement. Then capture CPU RESET recovery from
diagnostic ownership and package the captures with the generated bitstream hash:

```sh
python3 scripts/capture_checkpoint10.py /dev/ttyUSB1 \
    --output build/checkpoint10-board/uart-after-trace.dat
tar -czf /home/tyler/checkpoint10_board_evidence.tar.gz \
    -C /home/tyler/checkpoint10_src/build/checkpoint10-board \
    uart-first.dat uart-reset.dat trace.dat uart-after-trace.dat \
    bitstream.sha256 image-manifest.json vivado-reports
```

Press/release CPU RESET when the post-trace capture says it is ready; it must
report PASS again. Record the LED state and bitstream-generation console output.
Retain implementation source identity, image manifest and bitstream SHA-256 with
the synthesis/routed reports and all raw captures. These are the acceptance
conditions satisfied by the recorded 2026-10-11 board build; a changed RTL/image
or constraint build needs its own measurements and repeatable serial results.
Sv32, Linux boot and production QSPI loading remain later checkpoints.
