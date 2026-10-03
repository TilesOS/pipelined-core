# CPU functional coverage

The CPU testbench uses native SystemVerilog covergroups in
[`cpu_coverage.sv`](../tests/core/cpu_coverage.sv), bound to the simulation-only
`checkpoint4_top` wrapper. The model measures the current zero-wait, M-mode
RV32IMA CPU with Zicsr and Zifencei. It does not modify synthesizable CPU RTL.

The 2026-10-03 Ubuntu run measured **147/147 bins (100.00%)** across 51 fresh
simulation files. Before the targeted additions, the same model measured
138/147 bins (93.88%). All 41 Spike-checked program runs, the local directed
checks, and the collector integrity checks passed. The shared-controller
fixture self-test and cached CPU regression also passed.

## Run and reproduce

On the Ubuntu simulation host, after the existing Spike setup:

```sh
bash scripts/run_cpu_coverage.sh
```

The command runs the CPU slice, UART, RV32I, M/A/CSR, contention, and exception
gates, then two coverage-directed programs and collector integrity checks.
The default gate requires **100% of the explicitly defined bins**. Set
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
- `build/coverage/run-XXXXXX/*.dat`: counters from each simulator instance in this run.

Each run gets a fresh counter directory. The report rejects missing or unexpected
model bins and counts a bin as hit after at least one observation. Overall
coverage is `100 × hit bins / declared bins`; it is not the average of group
percentages. The CI lockstep job runs this gate and uploads the summary and raw
counters as `cpu-functional-coverage`.

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
| **Total** | **147** | Every bin remains in the denominator, including zero-hit bins |

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

## Interpretation

100% means every bin in this model was observed. It does not establish exhaustive
ISA correctness or cover caches, AXI, privilege modes, interrupts, MMU behavior,
all operand values, or every pipeline hazard interaction. Spike lockstep and the
directed assertions remain the correctness checks. Machine IDs and cycle counters
are checked locally because their values depend on the implementation.

The measured run and exact commands are recorded in
[`cpu-functional-coverage.txt`](checkpoints/evidence/cpu-functional-coverage.txt).
