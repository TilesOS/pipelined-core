# Early CPU debug path

Checkpoint 4 provides a trace path that keeps running when `manual_halt` freezes the CPU. It is an early bring-up UART transmitter, not the final ns16550a peripheral; checkpoint 10 will arbitrate the board TX pin with the standard UART.

## Retirement ring and serial packet

[`trace_ring_uart.sv`](../rtl/debug/trace_ring_uart.sv) records the newest 256 architectural events. Each entry holds the faulting or retired PC, instruction, M-mode privilege code, trap flag, cause, and trap value. An older entry is overwritten when the ring wraps. The dump button passes through a two-flop synchronizer and a stability counter. On a press, the debug engine freezes the CPU, waits two clocks so the last retirement reaches the ring, then sends a snapshot oldest first. Its state machine and UART TX run independently of CPU issue and retirement.

The UART format is 8N1 at nominal 115200 baud from a 50 MHz clock (`CLOCKS_PER_BIT=434`); simulation uses 8 clocks per bit. A packet contains four ASCII bytes `TRCE`, a little-endian unsigned 16-bit record count (0–256), then that many 17-byte records. A record is little-endian PC (4), instruction (4), cause (4), trap value (4), then one metadata byte: bits `[1:0]` privilege, bit 2 trap, bits `[7:3]` zero. A serial capture can scan for `TRCE`, use the count to read the exact payload length, and decode the final entries before a stall or trap. The packet has no CRC or flow control in this checkpoint; a future host decoder should reject truncated packets.

Decode a raw byte capture with `python3 scripts/decode_trace.py capture.bin` (or pipe the capture to its standard input). The decoder checks packet length and prints the oldest event first.

The forced-hang test retires five instructions, asserts `manual_halt`, then presses the button. It verifies five ordered records through the actual serial TX waveform while the CPU produces no more retirements. A second test retires 300 instructions and verifies the packet contains the newest 256 entries in order after wrap.

## ILA probe contract

The board top will mark these nets for Vivado ILA sampling in the 50 MHz core domain. [`checkpoint4_top.sv`](../rtl/top/checkpoint4_top.sv) exposes the currently implemented signals; probes for future subsystems are reserved here so the debug plan is stable before board bring-up.

| Probe | Width | Meaning and useful trigger |
|---|---:|---|
| `ila_pipeline[7:3]` | 5 | WB, MEM, EX, ID, IF valid; trigger when no retirement follows a nonempty pipeline. |
| `ila_pipeline[2:0]` | 3 | Decode dependency stall, EX redirect, EX fault; correlate branch kills and illegal traps. |
| `retire_valid`, `retire_pc`, `retire_cause`, `retire_tval` | 98 | Last architectural boundary and trap details. |
| `trace_count`, `trace_write_ptr`, `dump_busy` | 18 | Ring occupancy, wrap pointer, and active serial dump. |
| `manual_halt`, `dump_button`, `uart_tx` | 3 | Confirm a physical button press reaches the independent trace path. |
| Cache refill/miss/writeback | reserved | Add at checkpoint 9; trigger on a miss without refill completion. |
| AXI channel valid/ready and FIFO levels | reserved | Add at checkpoint 7; trigger on a request with no response. |
| MIG `init_calib_complete` and errors | reserved | Add at checkpoint 8; distinguish DDR calibration from CPU hangs. |

The first hardware trigger sequence is `retire_valid` going quiet with a stage valid, followed by a button dump. Capture 256 retired entries over UART and compare the last PC/trap with the ILA control state. No board timing or physical ILA capture is claimed before the x86-64 Vivado host and Nexys A7 are available.
