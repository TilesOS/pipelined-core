# CPU functional coverage

The CPU testbench uses native SystemVerilog covergroups in
[`cpu_coverage.sv`](../tests/core/cpu_coverage.sv), bound to the simulation-only
`checkpoint4_top` wrapper. The model measures the current zero-wait, M-mode
RV32IMA CPU with Zicsr and Zifencei. It does not modify synthesizable CPU RTL.

The expanded model has **243 total bins**, including **96 native hazard × trap ×
pipeline-stage cross bins**. Its pre-seed baseline was 212/243 (87.24%) overall,
and 65/96 (67.71%) for the cross. The original 147 single-point bins were already
complete. A fresh replay of the 30 retained seeds closed all 31 initial gaps,
reaching **243/243 overall and 96/96 cross bins (100%)**. All 71 scored Spike
program runs (3274 architectural events) and the collector integrity checks passed.
No CPU correctness bug was demonstrated. The baseline and closure evidence are kept separately so the initial
flat 100% report is not confused with the expanded measurement.

## Run and reproduce

On the Ubuntu simulation host, after the existing Spike setup:

```sh
bash scripts/run_cpu_coverage.sh
```

The command runs the CPU slice, UART, RV32I, M/A/CSR, contention, and exception
gates, then two coverage-directed programs, 30 retained constrained-random hazard/trap
seeds, and collector integrity checks.
The default gate requires **100% of all 243 explicitly defined bins**. Set
`CPU_COVERAGE_MIN_PERCENT` to change the required percentage for an exploratory
run; uncovered bins are always listed.

The system Verilator 5.032 does not compile covergroups. The setup helper builds
[official Verilator v5.052](https://github.com/verilator/verilator/releases/tag/v5.052)
at commit `ea338be98e1e838d3518809ce8899f85a009963c` under ignored
`build/tools/verilator-5.052`. Build prerequisites are Git, a C++ compiler, Make,
Perl, Autoconf, Flex, and Bison. No system installation is changed. The simulator
build defaults to four jobs; `COVERAGE_BUILD_JOBS` overrides this. An existing
covergroup-capable simulator can be selected with `VERILATOR_BIN`.

The pinned release translates native covergroups with `--coverage-user`; see
[Verilator's coverage documentation](https://verilator.org/guide/latest/simulating.html#covergroup-coverage).
Ordinary simulation commands continue to use the system simulator unless the
coverage options are explicitly selected.

Outputs are:

- `build/coverage/summary.txt`: overall and per-group hit/total counts and missing bins.
- `build/coverage/summary.json`: all named-bin counts and the coverage source SHA-256.
- `build/coverage/baseline.json`: the measurement before the retained seeds run.
- `build/coverage/seed-replay.json`: each seed's contribution and Spike-checked event count.
- `build/coverage/run-XXXXXX/*.dat`: counters from each simulator instance in this run.

Each run gets a fresh counter directory. The report rejects missing or unexpected
model bins and counts a bin as hit after at least one observation. Overall
coverage is `100 × hit bins / declared bins`; it is not the average of group
percentages. The CI lockstep job runs this gate and uploads the baseline, seed replay ledger,
summary and raw counters as `cpu-functional-coverage`.

To regenerate a report from one saved counter directory:

```sh
python3 scripts/report_cpu_coverage.py build/coverage/run-XXXXXX
```

## Fixed model

| Group | Bins | Qualification |
|---|---:|---|
| Instruction | 64 | Successful retirement of each modeled integer, M, A, CSR, or fence operation |
| Branch | 12 | Six branch operations × taken/fall-through outcome |
| Memory | 20 | Load/store operation × each legal byte lane; word accesses use lane zero |
| Trap | 9 | Implemented instruction/load/store misalignment and access faults, illegal instruction, EBREAK, M-mode ECALL |
| Divide | 10 | DIV/DIVU/REM/REMU ordinary and zero-divisor inputs, plus signed DIV/REM overflow |
| SC | 2 | Observed success/failure result in a nonzero destination register |
| Atomic ordering | 4 | Retired atomic with neither, release, acquire, or both ordering bits |
| CSR address | 16 | Selected canonical machine CSR addresses, including IDs and counter halves |
| CSR effect | 2 | Successful CSR retirement with/without an architectural CSR write |
| Destination | 2 | Destination-writing instruction naming x0/nonzero register |
| Pipeline flags | 6 | Clear/asserted observations for aggregate stall, redirect, and fault flags |
| Hazard × trap × stage | 96 | Histories of the faulting instruction, credited only at precise trap retirement |
| **Total** | **243** | Every reachable bin remains in the denominator, including zero-hit bins |

The CSR address list covers `mstatus`, `misa`, `mie`, `mtvec`, `mscratch`,
`mepc`, `mcause`, `mtval`, `mcycle`, `mcycleh`, `minstret`, `minstreth`,
`mvendorid`, `marchid`, `mimpid`, and `mhartid`. Counter aliases and `mip` are
outside this selected address list. ECALL and EBREAK count as traps rather than
successful instruction retirements.

Samples occur at the falling edge after retirement settles, including the final
trap when the controller immediately stops stepping. Branch and divide operands
come from reconstructed architectural GPR state before the current destination
write. Reset clears that state. Faulting instructions cannot credit legal
instruction or memory bins. Pipeline flag bins sample running cycles and are
coarse observations, not measurements of individual forwarding or stall causes.

The C++ harness writes counters before each DUT is destroyed. Each DUT owns its
own Verilated context, including the multiple instances used by reservation
tests. Lockstep sends `quit` before its bounded shutdown so successful runs can
flush counters; intentional comparator mismatch-injection runs do not contribute
to the coverage aggregate. Collector self-tests independently check final-trap
sampling, exclusion of faulting loads, divider classification, model lifetime
isolation, duplicate input paths, and rejection of incomplete counter data.

## Hazard, trap, and occupied-stage cross

The cross follows the instruction token through IF, ID, EX, MEM, and WB, retaining
its actual stall history. Flowing means the token occupied that stage without a
modeled hazard hold. RAW dependency, CSR/atomic/fence serialization, and divider
busy are derived from the core's actual control signals. Divider priority follows
the RTL's stall-selection order. Histories transfer with stage movement and are
dropped on redirects and fault flushes; a younger speculative fault never receives
credit if an older fault wins. The retired trap's PC must match the history token.

This is a cross of **hazard experienced × eventual exception × occupied stage**,
not exception-detection stage or unrelated stage occupancy at trap retirement.
Of the 96 tuples, 45 describe flowing instructions and 51 describe hazard holds.
The baseline hit 20 of the 51 hazard-hold tuples; all 31 missing cross scenarios
were hazard-hold cases.

The starting product is 4 hazard classes × 9 exception causes × 5 stages = 180.
The 84 exclusions were fixed before the baseline run:

- RAW and serialization hold IF/ID and inject an EX bubble. They do not hold
  tokens already occupying EX/MEM/WB: exclude 54 tuples.
- Divider stalls hold IF/ID and the divider's own EX token while MEM/WB drain.
  A retired trapping instruction cannot be that EX divider in this zero-wait
  fixture: legal DIV/REM does not trap, and failed fetches supply `0xffffffff`.
  Exclude 27 tuples for divider holds at EX/MEM/WB.
- ECALL/EBREAK and the failed-fetch encoding have no decoded GPR source, so RAW
  cannot hold them in ID: exclude 3 tuples.

Verilator v5.052 ignores explicit cross-bin select expressions with `COVERIGN`
warnings. To avoid silently ignored exclusions, the model uses supported
`ignore_bins` on the component coverpoints of five disjoint native crosses:

| Partition | Reachable native cross bins |
|---|---:|
| Flowing × nine exceptions × five stages | 45 |
| RAW × nine exceptions × IF | 9 |
| RAW × six source-using exceptions × ID | 6 |
| Serialization × nine exceptions × IF/ID | 18 |
| Divider busy × nine exceptions × IF/ID | 18 |
| **Total** | **96** |

The report aggregates those cross bins and does not count their component
coverpoints again. Runtime checks fail if an excluded tuple is actually observed;
exclusions cannot quietly hide a mismatched history or a changed fixture contract.
The model rejects `WAIT_MEMORY=1`; cache wait states require a different model.

## Reproduce the baseline and seed closure

To measure the same baseline without running the closing seeds:

```sh
CPU_CROSS_CLOSE=0 CPU_COVERAGE_MIN_PERCENT=0 bash scripts/run_cpu_coverage.sh
```

`gen_hazard_traps.py` constrains the desired trap, hazard mechanism, and occupied
stage, while a seed varies registers, operands, RAW producer operations, independent
instructions, and instruction spacing. The stimulus never writes coverage counters.
In particular, placing the trap too far behind the hazard leaves a tuple unhit,
which is why different schedules genuinely change the observed coverage.

The completed discovery run evaluated seeds 1000–1075: 76 distinct candidate
programs passed Spike lockstep. Thirty seeds contributed 31 newly hit tuples.
[`hazard_seeds.json`](../tests/core/hazard_seeds.json) retains those seeds, targets,
source SHA-256 values, and original contributions. CI replays those 30 programs
rather than repeating the discovery search. Each generated assembly source must
match its frozen hash before it runs.

To perform a new search from a saved baseline counter directory:

```sh
python3 scripts/close_cpu_cross_coverage.py build/coverage/run-XXXXXX \
  --baseline build/coverage/search-baseline.json --output build/coverage/search.json
```

The collector integrity suite also forces an older MEM access fault alongside a
younger EX illegal-instruction detection and verifies that only the older retired
fault contributes cross coverage. These self-test counters stay outside the scored
regression. No CPU correctness bug was demonstrated by this closure experiment.

## Interpretation

100% means every bin in this model was observed. It does not establish exhaustive
ISA correctness or cover caches, AXI, privilege modes, interrupts, MMU behavior,
all operand values, or every pipeline hazard interaction. Spike lockstep and the
directed assertions remain the correctness checks. Machine IDs and cycle counters
are checked locally because their values depend on the implementation.

The original single-point result is archived in
[`cpu-functional-coverage.txt`](checkpoints/evidence/cpu-functional-coverage.txt).
The expanded baseline is in [`cpu-cross-baseline.txt`](checkpoints/evidence/cpu-cross-baseline.txt),
and the completed discovery ledger is in
[`cpu-cross-seed-search.json`](checkpoints/evidence/cpu-cross-seed-search.json).
The fresh replay result and resume-safe wording are recorded in
[`cpu-cross-final.txt`](checkpoints/evidence/cpu-cross-final.txt), with final bin
counts and per-seed reference checks in the neighboring JSON files.
