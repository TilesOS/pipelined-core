# Checkpoint 4: first pipeline slice and independent debug

Status: local candidate on 2026-09-25. Clean CI evidence and final review are pending.

## Delivered

- Five explicit IF/ID/EX/MEM/WB stage registers, in-order single issue, dependency stalls, EX branch redirection, and retirement through the same Spike JSON protocol as checkpoint 3.
- M-mode RV32I subset: LUI, ADDI, ADD/SUB, LW, SW, BEQ, JAL, illegal-instruction and selected misalignment traps. A committed store can forward its word to the following load. Instruction and data memory are zero wait in this slice.
- 256-entry retirement/trap ring with synchronized/debounced button, independent debug FSM, and physical UART 8N1 byte transmitter. Defined ILA probe map in the [debug guide](../debug.md).
- Reproducible smoke, branch-flush, forced-hang UART, and 300-retirement ring-wrap tests in [`run_core_slice.sh`](../../scripts/run_core_slice.sh).

## Local evidence

`orb -m ece-dev bash -lc 'bash scripts/run_core_slice.sh'` passed with Verilator 5.032, RISC-V GCC 14.2, and pinned Spike 1.1.0:

```text
PASS: 7 architectural events (6 retirements, 1 trap) match Spike, including register and memory effects
PASS: real CPU retirement mismatch stopped at event 4
PASS: forced pipeline hang; button UART dumped five ordered PC/instruction records
PASS: captured UART packet decoded to the last retired PC
PASS: 8 architectural events (7 retirements, 1 trap) match Spike, including register and memory effects
PASS: 256-entry trace ring retained newest 256 of 300 retirements in UART order
```

The first smoke run exposed a store-to-load ordering error: the load in MEM observed memory before the older store in WB committed on that clock. The small reproducer is the existing adjacent `sw`/`lw` pair in `smoke.S`. Word forwarding from the committing WB store corrected it, and lockstep now reaches the trap. Verilator emitted no warnings in `build/core/verilator-build.log`.

## Remaining work

Checkpoint 5 completes the RV32I instruction set and precise exceptions with directed and randomized architectural tests. Later checkpoints replace zero-wait ports with cache/bus handshakes, add privilege, and connect the standard UART. No FPGA synthesis, board timing, or Linux boot is claimed by this checkpoint.
