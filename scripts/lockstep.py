#!/usr/bin/env python3
"""Advance a Verilator DUT and Spike together, stopping at the first retirement mismatch."""

import argparse
from collections import deque
import json
import os
import pty
import queue
import re
import select
import subprocess
import sys
import termios
import threading
import time

COMMIT = re.compile(r"^core\s+0:\s+(\d)\s+(0x[0-9a-f]+)\s+\((0x[0-9a-f]+)\)(.*)$")
TRACE = re.compile(r"^core\s+0:\s+(0x[0-9a-f]+)\s+\((0x[0-9a-f]+)\).*$")
REG = re.compile(r"\bx\s*(\d+)\s+(0x[0-9a-f]+)")
CSR = re.compile(r"\bc(\d+)_[a-zA-Z0-9_]+\s+(0x[0-9a-f]+)")
MEM = re.compile(r"\bmem\s+(0x[0-9a-f]+)(?:\s+(0x[0-9a-f]+))?")
TRAP = re.compile(r"^core\s+0: exception (trap_[a-z_]+), epc (0x[0-9a-f]+)$")
TVAL = re.compile(r"^core\s+0:\s+tval (0x[0-9a-f]+)$")
HEX = re.compile(r"^0x[0-9a-f]+$")
CAUSES = {
    "instruction_address_misaligned": 0,
    "instruction_access_fault": 1,
    "illegal_instruction": 2,
    "breakpoint": 3,
    "load_address_misaligned": 4,
    "load_access_fault": 5,
    "store_address_misaligned": 6,
    "store_access_fault": 7,
    "user_ecall": 8,
    "supervisor_ecall": 9,
    "machine_ecall": 11,
    "instruction_page_fault": 12,
    "load_page_fault": 13,
    "store_page_fault": 15,
}


class LineStream:
    def __init__(self, file):
        self.lines = queue.Queue()
        threading.Thread(target=self._pump, args=(file,), daemon=True).start()

    def _pump(self, file):
        for line in file:
            self.lines.put(line.rstrip("\r\n"))
        self.lines.put(None)

    def get(self, source, timeout=10):
        try:
            line = self.lines.get(timeout=timeout)
        except queue.Empty as exc:
            raise RuntimeError(f"timeout waiting for {source}") from exc
        if line is None:
            raise RuntimeError(f"{source} closed unexpectedly")
        return line


def write_command(proc, command):
    if proc.poll() is not None:
        raise RuntimeError(f"process exited before {command!r}: {proc.returncode}")
    proc.stdin.write(command + "\n")
    proc.stdin.flush()


class SpikePTY:
    """Drive Spike's interactive debugger without allowing a run-ahead step."""

    def __init__(self, command):
        self.master, slave = pty.openpty()
        attributes = termios.tcgetattr(slave)
        attributes[3] &= ~termios.ECHO
        termios.tcsetattr(slave, termios.TCSANOW, attributes)
        self.process = subprocess.Popen(command, stdin=slave, stdout=subprocess.DEVNULL,
                                        stderr=slave, close_fds=True)
        os.close(slave)
        self.pending = b""
        try:
            self._response()
        except Exception:
            self.close()
            raise

    def _response(self):
        deadline = time.monotonic() + 10
        while True:
            prompt = re.search(rb"(?:^|\r?\n): $", self.pending)
            if prompt:
                result = self.pending[:prompt.start()].decode(errors="replace")
                self.pending = self.pending[prompt.end():]
                return [line.strip() for line in result.splitlines() if line.strip()]
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise RuntimeError("timeout waiting for Spike prompt")
            ready, _, _ = select.select([self.master], [], [], remaining)
            if not ready:
                raise RuntimeError("timeout waiting for Spike prompt")
            chunk = os.read(self.master, 65536)
            if not chunk:
                raise RuntimeError("Spike terminal closed")
            self.pending += chunk

    def command(self, text):
        if self.process.poll() is not None:
            raise RuntimeError(f"Spike exited: {self.process.returncode}")
        os.write(self.master, (text + "\n").encode())
        return self._response()

    def close(self):
        if self.process.poll() is None:
            self.process.terminate()
        try:
            self.process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait()
        os.close(self.master)


def spike_pc(spike):
    answers = [line for line in spike.command("pc 0") if HEX.fullmatch(line)]
    if len(answers) != 1:
        raise RuntimeError(f"Spike did not answer pc 0: {answers!r}")
    return int(answers[0], 16)


def spike_step(spike):
    return [line for line in spike.command("run 1") if line != ":"]


def align_spike(spike, entry):
    for skipped in range(32):
        if spike_pc(spike) == entry:
            return skipped
        spike_step(spike)
    raise RuntimeError(f"Spike did not reach ELF entry 0x{entry:08x}")


def load_size(insn):
    opcode = insn & 0x7f
    funct3 = (insn >> 12) & 7
    if opcode == 0x03:
        return {0: 1, 1: 2, 2: 4, 4: 1, 5: 2}.get(funct3)
    if opcode == 0x2f:
        return {2: 4}.get(funct3)
    return None


def parse_spike_step(lines):
    commits = [COMMIT.fullmatch(line) for line in lines]
    commits = [match for match in commits if match]
    traps = [TRAP.fullmatch(line) for line in lines]
    traps = [match for match in traps if match]
    if len(commits) + len(traps) != 1:
        raise RuntimeError(f"expected one Spike retirement or trap, got: {lines!r}")
    if traps:
        trap = traps[0]
        name = trap.group(1).removeprefix("trap_")
        if name not in CAUSES:
            raise RuntimeError(f"unmapped Spike trap: {name}")
        traces = [match for line in lines if (match := TRACE.fullmatch(line))]
        if len(traces) != 1 or int(traces[0].group(1), 16) != int(trap.group(2), 16):
            raise RuntimeError(f"missing or inconsistent Spike trap instruction: {lines!r}")
        tval = next((int(m.group(1), 16) for line in lines
                     if (m := TVAL.fullmatch(line))), 0)
        return {"trap": True, "pc": int(trap.group(2), 16),
                "insn": int(traces[0].group(2), 16),
                "cause": CAUSES[name], "tval": tval, "raw": lines}
    match = commits[0]
    tail = match.group(4)
    insn = int(match.group(3), 16)
    regs = {int(reg): int(value, 16) for reg, value in REG.findall(tail)}
    csrs = {int(addr): int(value, 16) for addr, value in CSR.findall(tail)}
    reads = []
    writes = {}
    for mem in MEM.finditer(tail):
        addr = int(mem.group(1), 16)
        value_text = mem.group(2)
        if value_text:
            size = (len(value_text) - 2) // 2
            value = int(value_text, 16)
            for byte in range(size):
                writes[addr + byte] = (value >> (byte * 8)) & 0xff
        else:
            size = load_size(insn)
            if size is None:
                raise RuntimeError(f"cannot infer Spike read size: 0x{insn:08x}")
            reads.extend(range(addr, addr + size))
    return {"trap": False, "pc": int(match.group(2), 16), "insn": insn,
            "priv": int(match.group(1)), "regs": regs, "csrs": csrs,
            "reads": sorted(reads), "writes": writes, "raw": lines}


def dut_effects(event):
    addr = int(event["mem_addr"], 16)
    aligned = addr & ~3
    reads = [aligned + byte for byte in range(4)
             if (event["mem_rmask"] >> byte) & 1]
    data = int(event["mem_wdata"], 16)
    writes = {aligned + byte: (data >> (byte * 8)) & 0xff
              for byte in range(4) if (event["mem_wmask"] >> byte) & 1}
    regs = ({event["rd"]: int(event["rd_data"], 16)}
            if event["rd"] else {})
    csrs = {int(item["addr"], 16): int(item["value"], 16)
            for item in event.get("csr_writes", [])}
    return reads, writes, regs, csrs


def differences(event, reference):
    fields = {}
    dut_pc = int(event["pc"], 16)
    if dut_pc != reference["pc"]:
        fields["pc"] = (f"0x{dut_pc:08x}", f"0x{reference['pc']:08x}")
    if event["trap"] != reference["trap"]:
        fields["trap"] = (event["trap"], reference["trap"])
    insn = int(event["insn"], 16)
    if insn != reference["insn"]:
        fields["insn"] = (f"0x{insn:08x}", f"0x{reference['insn']:08x}")
    if reference["trap"]:
        for key in ("cause", "tval"):
            dut_value = int(event[key], 16)
            if dut_value != reference[key]:
                fields[key] = (f"0x{dut_value:08x}", f"0x{reference[key]:08x}")
        return fields
    if event["priv"] != reference["priv"]:
        fields["priv"] = (event["priv"], reference["priv"])
    reads, writes, regs, csrs = dut_effects(event)
    for name, dut, spike in (("register writes", regs, reference["regs"]),
                              ("CSR writes", csrs, reference["csrs"]),
                              ("memory reads", reads, reference["reads"]),
                              ("memory writes", writes, reference["writes"])):
        if dut != spike:
            fields[name] = (dut, spike)
    return fields


def spike_registers(spike):
    values = []
    for reg in range(32):
        answers = [line for line in spike.command(f"reg 0 {reg}")
                   if HEX.fullmatch(line)]
        if len(answers) != 1:
            raise RuntimeError(f"Spike did not answer register {reg}")
        values.append(int(answers[0], 16))
    return values


def spike_csrs(spike):
    result = {}
    for name in ("mstatus", "mepc", "mcause", "mtval", "mtvec",
                 "sstatus", "sepc", "scause", "stval", "satp"):
        answers = [line for line in spike.command(f"reg 0 {name}")
                   if HEX.fullmatch(line)]
        if len(answers) == 1:
            result[name] = int(answers[0], 16)
    return result


def run(args):
    spike_cmd = [args.spike, "--isa=rv32ima_zicsr_zifencei", "--priv=m",
                 f"--pc=0x{args.entry:08x}", "-m0x80000000:0x10000",
                 "-d", "-l", "--log-commits", args.elf]
    spike = SpikePTY(spike_cmd)
    dut = subprocess.Popen([args.dut], stdin=subprocess.PIPE,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           text=True, bufsize=1)
    dut_lines = LineStream(dut.stdout)
    history = deque(maxlen=8)
    dut_regs = [None] * 32
    dut_regs[0] = 0
    dut_csrs = {}
    memory = {}
    try:
        skipped = align_spike(spike, args.entry)
        print(f"Spike aligned at 0x{args.entry:08x} after {skipped} startup instructions")
        retired = 0
        traps = 0
        cycles_without_retire = 0
        while retired < args.limit:
            write_command(dut, "step")
            event = json.loads(dut_lines.get("Verilator"))
            if event["kind"] == "cycle":
                cycles_without_retire += 1
                if cycles_without_retire > args.watchdog:
                    raise RuntimeError(f"no DUT retirement for {args.watchdog} cycles")
                continue
            if event["kind"] == "done":
                raise RuntimeError(f"DUT ended after {retired}/{args.limit} retirements")
            if event["kind"] != "retire" or event["order"] != retired:
                raise RuntimeError(f"invalid or out-of-order DUT event: {event!r}")
            cycles_without_retire = 0
            if args.inject == f"rd@{retired}":
                event["rd_data"] = f"{(int(event['rd_data'], 16) ^ 1):08x}"
            if args.inject == f"store@{retired}":
                event["mem_wdata"] = f"{(int(event['mem_wdata'], 16) ^ 1):08x}"
            if args.inject == f"cause@{retired}":
                event["cause"] = f"{(int(event['cause'], 16) ^ 1):08x}"
            reference = parse_spike_step(spike_step(spike))
            diff = differences(event, reference)
            if diff:
                kind = "trap event" if event["trap"] or reference["trap"] else "retirement"
                print(f"DIVERGENCE at {kind} {retired}", file=sys.stderr)
                print(json.dumps({"difference": diff, "dut": event,
                                  "spike": reference, "recent": list(history)},
                                 indent=2), file=sys.stderr)
                print("Spike GPRs: " + " ".join(
                    f"x{i}=0x{value:08x}" for i, value in
                    enumerate(spike_registers(spike))), file=sys.stderr)
                print("DUT known GPRs: " + " ".join(
                    f"x{i}=0x{value:08x}" for i, value in
                    enumerate(dut_regs) if value is not None), file=sys.stderr)
                print("Spike CSRs: " + " ".join(
                    f"{name}=0x{value:08x}" for name, value in
                    spike_csrs(spike).items()), file=sys.stderr)
                print("DUT known CSR writes: " + " ".join(
                    f"0x{addr:03x}=0x{value:08x}" for addr, value in
                    sorted(dut_csrs.items())), file=sys.stderr)
                print("DUT known memory bytes: " + " ".join(
                    f"0x{addr:08x}=0x{value:02x}" for addr, value in
                    sorted(memory.items())), file=sys.stderr)
                return 1
            _, writes, regs, csrs = dut_effects(event)
            for reg, value in regs.items():
                dut_regs[reg] = value
            memory.update(writes)
            dut_csrs.update(csrs)
            history.append({"order": retired, "pc": event["pc"], "insn": event["insn"]})
            traps += int(event["trap"])
            retired += 1
        if args.require_done:
            write_command(dut, "step")
            event = json.loads(dut_lines.get("Verilator"))
            if event["kind"] != "done":
                raise RuntimeError(f"DUT emitted more than {args.limit} retirements")
        print(f"PASS: {retired} architectural events ({retired - traps} retirements, "
              f"{traps} trap{'s' if traps != 1 else ''}) match Spike, "
              "including register and memory effects", flush=True)
        return 0
    finally:
        if dut.poll() is None:
            dut.terminate()
        try:
            dut.wait(timeout=2)
        except subprocess.TimeoutExpired:
            dut.kill()
            dut.wait()
        spike.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--spike", required=True)
    parser.add_argument("--dut", required=True)
    parser.add_argument("--elf", required=True)
    parser.add_argument("--entry", type=lambda s: int(s, 0), default=0x80000000)
    parser.add_argument("--limit", type=int, default=7)
    parser.add_argument("--watchdog", type=int, default=1000)
    parser.add_argument("--require-done", action="store_true")
    parser.add_argument("--inject", default="", help="test-only rd@N, store@N, or cause@N fault")
    args = parser.parse_args()
    if args.limit <= 0 or args.watchdog <= 0:
        parser.error("limit and watchdog must be positive")
    try:
        return run(args)
    except (OSError, RuntimeError, ValueError, KeyError, json.JSONDecodeError) as exc:
        print(f"LOCKSTEP ERROR: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
