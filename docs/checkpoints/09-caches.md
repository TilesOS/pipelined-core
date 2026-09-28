# Checkpoint 9: L1 caches and cached CPU integration

Status: complete in RTL simulation on 2026-09-28. The implementation and this
record are committed together. No cached-CPU bitstream, resource report, or
board timing result is claimed here.

## Delivered

- Separate physically indexed/tagged 8 KiB L1s, two ways, 128 sets, and 32-byte
  lines. Lookup reads are clocked. The I-cache is read-only; the D-cache is
  blocking, write-back/write-allocate, with per-line dirty bits and two-way LRU.
  Data arrays have no reset; reset clears validity and dirty metadata.
- Two-beat, 128-bit INCR refills/writebacks on fixed masters 0 (I) and 1 (D).
  Failed refills do not install a line; failed writebacks retain dirty data.
  The existing width bridge handles uncached DDR and exact narrow ROM/MMIO
  byte addresses. Only `0x80000000..0x877fffff` can allocate a cache line.
  The entire top 8 MiB DMA pool bypasses both caches, including instruction
  fetch. Unmapped accesses and ROM writes fault without reaching AXI.
- Optional blocking memory handshakes in the existing five-stage CPU. A
  stalled MEM stage drains WB once and holds younger stages; a pending WB
  store holds retirement until the cache/bus response. Loads, store allocation,
  and uncached write errors suppress younger architectural effects. The
  zero-wait fixture remains available for the earlier regression gates.
- Full `FENCE.I`: serialize older instructions and writes, clean every dirty
  D-cache line through its final AXI B response, discard/drain outstanding
  instruction fetch, invalidate the I-cache, then flush and refetch the front
  end. Plain `FENCE` waits for older CPU accesses; it does not clean unrelated
  dirty data or wait for unrelated DMA jobs.
- LR/SC and every AMO retain the checkpoint 6 semantics through the D-cache.
  The integrated fabric blocks new competing AW requests during the atomic
  interval while allowing already granted W/B traffic to drain. Atomic reads
  and SC evaluation wait for those older writes. Reservation snooping tracks
  byte strobes at word granularity on every external burst beat. A conflicting
  store clears LR; a masked store to another word preserves it.
- `rv32_cached_core` and `checkpoint9_top` connect the real CPU/cache paths to
  the four-master fabric and asynchronous MIG crossing. Master 3 is restricted
  to the uncached DMA pool; attempts to write cached DDR return DECERR. The `cpu_run` input can keep CPU/L1 state reset while the loader uses the
  calibrated bus. Reset release follows `masters_ready`; calibration loss resets CPU, L1 metadata,
  and transport together. UART retirement/trap dumps remain independent of
  cache progress. Cache/fence states have ILA debug attributes and traffic
  counters are exposed.
- `scripts/run_checkpoint9.sh`, directed/randomized programs, injected-fault
  and contention checks, and the CI checkpoint gate. `lockstep.py --memory`
  selects the larger physical DDR model while preserving its old default.

## Evidence

On OrbStack Ubuntu with Verilator 5.032, RISC-V GCC 14.2, and the pinned Spike
1.1.0 build:

```sh
bash scripts/run_checkpoint9.sh
bash scripts/run_lockstep_smoke.sh --self-test
bash scripts/run_core_slice.sh
bash scripts/run_rv32i.sh
bash scripts/run_checkpoint6.sh
bash scripts/run_checkpoint7.sh
bash scripts/lint_checkpoint8_board.sh
bash scripts/run_checkpoint8_traffic.sh
python3 scripts/check_flash_layout.py
```

The checkpoint 9 gate builds without default Verilator warnings and covers:

- Two seeded runs of 279 L1 operations each: hits across both line beats,
  subword stores, dirty LRU eviction, all 256 dirty lines, delayed final B,
  physical boundary/bypass checks, held responses, and refill/writeback error
  recovery.
- 21 retirement-by-retirement Spike runs (3,024 architectural events) covering directed RV32I/M/A/CSR and
  fences, twice-rewritten previously executable cached code, executable DMA
  code, and cached/uncached boundary accesses. Four randomized RV32I seeds
  produce 447 events each; four randomized M seeds produce 227 events each.
  Executable-page and DMA-window programs also pass core/MIG half-periods
  3/11 and 11/3 in addition to the default 5/7, with seeded backpressure.
- Real competing writes through the fabric and CDC: same-word LR interference,
  different-word strobe preservation, an overlapping second burst beat,
  same-hart reservation clearing, AMO lock contention, and an older writer
  that delays W for 35 cycles. A DMA attempt to cached DDR is rejected.
- Injected instruction refill, data refill, uncached store, dirty eviction,
  and fence clean errors. Each reports the expected faulting PC with no
  younger retirement or reported register/memory effect.
- Calibration loss during an in-flight instruction refill and after a dirty
  store, followed by seven ordered restart events. A hung instruction refill
  still permits the button UART to dump the last retired PC.

A temporary Ubuntu 24.04 container with Verilator 5.020 also passed the cache
unit gate and the directed cached-system checks, including contention, faults,
calibration restart, and stalled UART. This verifies the older simulator used
by the repository's CI base image; the Spike comparisons above ran on 5.032.
The earlier CPU, lockstep first-divergence, AXI, and checkpoint 8 simulation
regressions passed. `git diff --check` and Python/shell syntax checks passed.
A compact saved output is [checkpoint 9 evidence](evidence/09-simulation.txt).

The contention reproducer caught a snoop bug before acceptance: using the
whole AXI address span invalidated LR even when WSTRB updated only a neighboring
word. Snoop masks now include exactly the written word lanes for each accepted
beat. The regression preserves both the different-word and second-beat cases.

## CI image-loading follow-up

The first [GitHub Actions run](https://github.com/TilesOS/pipelined-core/actions/runs/36446453814)
failed in the cached smoke comparison on Ubuntu 24.04 / Verilator 5.020.
The final instruction was loaded as `0x00ffffff` instead of `0xffffffff`:
the generated hex file had no whitespace after its final byte token, and
that simulator's `$readmemh` omitted the unterminated token. The earlier
5.020 portability checks did not compare the final trap instruction against
Spike, so they missed this difference.

The image writer now appends a newline. The same seven-event smoke test
reproduces the failure without it and passes with it. A fresh Verilator 5.020
build passes the unit/directed cached-system gates and all 21 Spike comparisons
(3,024 architectural events); the full checkpoint 9 gate also passes on 5.032.
The CPU/cache RTL and binary program images are unchanged. See
[the fix evidence](evidence/09-ci-image-loading.txt).

## Scope and next step

This is still a single-hart M-mode CPU that halts on a trap. Standard devices,
trap entry/return, and privilege are checkpoint 10; Sv32/TLB/page-walker work is
checkpoint 11. The peripheral AXI boundary is exposed for those devices; it
is not a complete board ROM/UART subsystem yet.

DMA is noncoherent. Master 3 cannot access cached DDR; loader/debug master 2
requires a reset/reinitialization protocol before modifying cached memory.
Calibration loss aborts work and discards dirty L1 state, as a system reset;
it is not a memory-preserving runtime recovery mechanism.

For deferred writeback failure during `FENCE.I`, this checkpoint uses a
fail-stop diagnostic: cause 7 and the fence PC as `tval`, retains dirty data,
and leaves the I-cache valid. This is a platform error policy tested directly,
not a Spike comparison of an injected hardware failure. It requires review
when checkpoint 10 introduces trap routing/recovery.

Checkpoint 8's measured board shell remains unchanged and still uses synthetic
CPU-like traffic. `checkpoint9_top` is the synthesizable MIG integration
boundary. Actual FPGA BRAM inference, CPU/cache utilization, 50 MHz timing,
and board execution must be measured on the later integrated board build;
the previous shell's timing and bandwidth do not establish those results.
