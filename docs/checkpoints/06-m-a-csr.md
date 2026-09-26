# Checkpoint 6: M/A, machine CSRs, and fences

Status: complete for the zero-wait M-mode CPU on 2026-09-26. Implementation commit: `56c5dd3`. The local OrbStack Ubuntu gate passed; the repository CI workflow includes the same checkpoint test script.

## Delivered

- All eight RV32M instructions. Signed and unsigned division/remainder use a 32-step iterative divider; zero divisors and signed overflow return the architectural results without trapping.
- RV32A word LR/SC and all nine word AMO operations, including acquire/release encodings. Atomics serialize through the zero-wait memory path. SC returns zero on success and one on failure. An external committed-store address invalidates an overlapping reservation; `atomic_lock` keeps competing writers out of the MEM-to-WB atomic interval.
- Six Zicsr instruction forms for implemented machine CSRs: `mstatus`, fixed `misa`, `mie`, `mtvec`, `mscratch`, `mepc`, `mcause`, `mtval`, `mip`, machine identity, and the 64-bit `mcycle`/`minstret` halves and read aliases. Unsupported and read-only CSR operations trap; each explicit CSR write appears in the retirement trace.
- Serializing `FENCE`, `FENCE.TSO`, and `FENCE.I`. In the zero-wait model, `FENCE.I` drains older stores and flushes/refetches younger instructions. A self-modifying-code program compares successfully with Spike.

## Evidence

On OrbStack Ubuntu with Verilator 5.032, RISC-V GCC 14.2, and pinned Spike 1.1.0:

```text
bash scripts/run_lockstep_smoke.sh --self-test
bash scripts/run_core_slice.sh
bash scripts/run_rv32i.sh
bash scripts/run_checkpoint6.sh
PASS: 22 directed M, 25 directed A, 28 CSR, and 11 FENCE.I architectural events
PASS: four randomized M seeds, 227 architectural events each
PASS: ten precise atomic and CSR exception cases
PASS: external same-word reservation invalidation, other-word preservation,
      same-hart conflicting store invalidation, and AMO lock contention
PASS: 64-bit mcycle/minstret halves and counter write/read ordering
```

The checkpoint 3–5 regressions also passed. The fresh Verilator build emitted no warnings; syntax checks, `git diff --check`, and the flash allocation checker passed.

The directed tests exposed two implementation errors before the final gate: signed division inherited an unsigned expression context, and a failed SC's status was overwritten as it entered WB. Both were corrected. Spike allows a same-hart store to leave an LR reservation valid, while this project's architecture contract requires a conflicting store to clear it; that case is checked directly against the contract instead of forced into Spike lockstep.

## Scope and next step

This is a single-hart, zero-wait M-mode slice. External writers must honor `atomic_lock`; the actual multi-master arbiter, cache serialization, and full `FENCE.I` D-cache writeback are later checkpoints. Machine trap entry/return, interrupts, and S/U privilege are checkpoint 10. Checkpoint 7 adds the AXI fabric, width bridge, and clock crossing with randomized transaction and reset tests.
