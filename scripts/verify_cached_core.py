#!/usr/bin/env python3
"""Directed observations that cannot be represented by single-hart Spike."""
import argparse
import json
import os
import pathlib
import re
import subprocess


def run(dut, image, **environment):
    env = dict(os.environ, CACHE_IMAGE=str(image), **environment)
    proc = subprocess.Popen([str(dut)], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True, env=env)
    events = []
    try:
        for _ in range(30000):
            proc.stdin.write("step\n")
            proc.stdin.flush()
            event = json.loads(proc.stdout.readline())
            if event["kind"] == "retire":
                events.append(event)
            if event["kind"] == "done":
                break
        else:
            raise AssertionError("cached CPU watchdog")
        proc.stdin.write("quit\n")
        proc.stdin.flush()
        _, stderr = proc.communicate(timeout=10)
        assert proc.returncode == 0, stderr
        assert events and events[-1]["trap"], events
        return events, stderr
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("build", type=pathlib.Path)
    args = parser.parse_args()
    build = args.build.resolve()
    dut = build / "core_obj/Vcached_core_sim"
    events, diagnostics = run(dut, build / "uncached_executable.hex")
    instructions = [e for e in events if e["pc"] == "87800000"]
    assert [int(e["rd_data"], 16) for e in instructions] == [10, 20], events
    traffic = re.search(r"I misses=(\d+) bypass=(\d+) D misses=(\d+) writebacks=(\d+) bypass=(\d+)", diagnostics)
    assert traffic and int(traffic[2]) >= 4 and int(traffic[3]) == int(traffic[4]) == 0 and int(traffic[5]) == 3, diagnostics
    print("PASS: uncached executable DMA pages bypass both L1s and observe updated code")
    # Same-word, different-word, burst-overlap, and same-hart store cases.
    for name, mode, sc_pc, load_pc, status, value in (
        ("atomic_contention", "1", 20, 24, 1, 9),
        ("atomic_contention", "2", 20, 24, 0, 6),
        ("burst_reservation", "4", 16, 20, 1, 9),
        ("reservation_store", "0", 20, 24, 1, 5),
    ):
        events, diagnostics = run(dut, build / f"{name}.hex", DMA_TEST_MODE=mode)
        by_pc = {int(e["pc"], 16): e for e in events}
        assert int(by_pc[0x80000000 + sc_pc]["rd_data"], 16) == status, events
        assert int(by_pc[0x80000000 + load_pc]["rd_data"], 16) == value, events
        if mode != "0":
            assert "DMA done=1" in diagnostics, diagnostics
    # Writer arriving during AMO waits until commit. A writer admitted earlier
    # holds W for 35 cycles: AMO must let it drain and observe its value.
    for mode, old_value, loaded_value in (("3", 5, 9), ("5", 9, 14)):
        events, diagnostics = run(dut, build / "amo_contention.hex", DMA_TEST_MODE=mode)
        amo = next(e for e in events if int(e["pc"], 16) == 0x8000000c)
        load = next(e for e in events if int(e["mem_rmask"]) and e["insn"][-2:] == "03")
        assert int(amo["rd_data"], 16) == old_value and int(amo["mem_wdata"], 16) == old_value + 5, events
        assert int(load["rd_data"], 16) == loaded_value, events
        assert "DMA done=1" in diagnostics, diagnostics
        if mode == "3":
            assert "blocked=1" in diagnostics, diagnostics
    # An attempt to reach cached DDR through the noncoherent DMA master faults
    # at the fabric. It cannot create a hidden cache alias.
    events, diagnostics = run(dut, build / "atomic_contention.hex", DMA_TEST_MODE="6")
    assert "DMA done=1" in diagnostics, diagnostics
    assert int(next(e for e in events if e["pc"] == "80000018")["rd_data"], 16) == 6, events
    print("PASS: LR/SC same/different word and burst interference, AMO arbitration/drain, cached DMA rejection")

    for name, env, pc, cause, tval, count in (
        ("smoke", {"FAIL_READ_ADDR": "80000000"}, 0, 1, 0x80000000, 1),
        ("fault_load", {"FAIL_READ_ADDR": "80004000"}, 4, 5, 0x80004000, 2),
        ("fault_store", {"FAIL_WRITE_ADDR": "87800000"}, 8, 7, 0x87800000, 3),
        ("fault_eviction", {"FAIL_WRITE_ADDR": "80004000"}, 24, 7, 0x80006000, 7),
        ("fault_fence", {"FAIL_WRITE_ADDR": "80004000"}, 12, 7, 0x8000000c, 4),
    ):
        events, _ = run(dut, build / f"{name}.hex", **env)
        fault = events[-1]
        assert len(events) == count and int(fault["pc"], 16) == 0x80000000 + pc, events
        assert int(fault["cause"], 16) == cause and int(fault["tval"], 16) == tval, fault
        assert fault["mem_rmask"] == fault["mem_wmask"] == fault["rd"] == 0, fault
    print("PASS: precise instruction/refill/store/eviction/FENCE.I AXI faults; younger work suppressed")
    subprocess.run([str(dut), "--reset-test"], check=True,
                   env=dict(os.environ, CACHE_IMAGE=str(build / "smoke.hex")))
    subprocess.run([str(dut), "--hang-test"], check=True,
                   env=dict(os.environ, CACHE_IMAGE=str(build / "executable_page.hex")))


if __name__ == "__main__":
    main()
