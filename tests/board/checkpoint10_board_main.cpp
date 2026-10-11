#include "Vcheckpoint10_board_sim.h"
#include "verilated.h"
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <string>

struct Serial {
    unsigned period = 432;
    int left = -1, bit = 0, previous = 1;
    uint8_t value = 0;
    std::string bytes;
    void sample(int tx) {
        if (left < 0) {
            if (previous && !tx) { left = period + period/2; bit = 0; value = 0; }
        } else if (--left == 0) {
            if (bit < 8) { value |= tx << bit++; left = period; }
            else {
                if (!tx) { std::fprintf(stderr, "UART framing error\n"); std::exit(1); }
                bytes.push_back(value); left = -1;
            }
        }
        previous = tx;
    }
};
struct Simulation {
    Vcheckpoint10_board_sim dut;
    Serial uart;
    uint64_t ticks = 0;
    unsigned core_half = 5, mig_half = 7;
    Simulation() {
        if (const char* s = std::getenv("CORE_HALF")) core_half = std::strtoul(s, nullptr, 10);
        if (const char* s = std::getenv("MIG_HALF")) mig_half = std::strtoul(s, nullptr, 10);
        if (!core_half || !mig_half) std::exit(2);
        dut.rst_n = 0; dut.calibrated = 0; dut.uart_rx = 1; dut.dump_button = 0;
        for (unsigned i = 0; i < 100; ++i) tick();
        dut.rst_n = 1;
        for (unsigned i = 0; i < 100; ++i) step();
        if (dut.led & 3) std::exit(1);
        dut.calibrated = 1;
    }
    void tick() {
        ++ticks;
        dut.core_clk = (ticks/core_half) & 1;
        dut.mig_clk = (ticks/mig_half) & 1;
        dut.eval();
    }
    void step() {
        while (dut.core_clk) tick();
        while (!dut.core_clk) tick();
        uart.sample(dut.uart_tx);
        if (dut.led & 4) { std::fprintf(stderr, "Board failure LED\n"); std::exit(1); }
    }
    void send(uint8_t value) {
        for (unsigned bit = 0; bit < 10; ++bit) {
            dut.uart_rx = bit == 0 ? 0 : bit == 9 ? 1 : (value >> (bit-1)) & 1;
            // PC's nominal 115200 baud, rather than DUT's divisor-27 rate.
            for (unsigned i = 0; i < 434; ++i) step();
        }
    }
    void boot() {
        uart = Serial{};
        bool sent = false;
        size_t shown = 0;
        for (unsigned i = 0; i < 100000000; ++i) {
            step();
            if (std::getenv("BOOT_DIAGNOSTICS") && i && i % 1000000 == 0)
                std::fprintf(stderr, "board cycles=%u pc=%08x cause=%08x tval=%08x LEDs=%x\n",
                    i, dut.last_pc, dut.last_cause, dut.last_tval, dut.led);
            while (shown < uart.bytes.size()) std::putchar(uart.bytes[shown++]);
            if (!sent && uart.bytes.find("CHECKPOINT10 UART RX READY: send K\r\n") != std::string::npos) {
                send('K'); sent = true;
            }
            if ((dut.led & 8) && uart.bytes.find("CHECKPOINT10 UART RX/PLIC PASS\r\n") != std::string::npos) {
                if (!sent || uart.bytes.find("OpenSBI v1.7") == std::string::npos ||
                    uart.bytes.find("CHECKPOINT10 SBI TIMER/PMP PASS\r\n") == std::string::npos ||
                    (dut.led & 3) != 3) std::exit(1);
                return;
            }
        }
        std::fprintf(stderr, "Board boot watchdog, pc=%08x cause=%08x tval=%08x LEDs=%x\n",
            dut.last_pc, dut.last_cause, dut.last_tval, dut.led); std::exit(1);
    }
};
int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    std::setvbuf(stdout, nullptr, _IONBF, 0);
    Simulation sim;
    // Interrupt an in-progress hardware copy, then require a fresh full copy.
    for (unsigned i = 0; i < 1000; ++i) sim.step();
    sim.dut.calibrated = 0;
    for (unsigned i = 0; i < 100; ++i) sim.step();
    if (sim.dut.led & 3) return 1;
    sim.dut.calibrated = 1;
    sim.boot();
    std::puts("PASS: ROM-to-DDR readback, OpenSBI timer/PMP and physical UART RX-to-S PLIC path");
    sim.dut.rst_n = 0; sim.dut.calibrated = 0;
    for (unsigned i = 0; i < 100; ++i) sim.step();
    sim.dut.rst_n = 1; sim.dut.calibrated = 1;
    sim.boot();
    std::puts("PASS: board CPU RESET reload/retest");
    // One-way ownership must preserve a complete diagnostic packet and tail.
    sim.uart = Serial{};
    sim.uart.period = 434;
    sim.dut.dump_button = 1;
    unsigned count = 0, expected = 0;
    for (unsigned i = 0; i < 20000000; ++i) {
        sim.step();
        if (sim.uart.bytes.size() >= 6 && !expected) {
            if (sim.uart.bytes.substr(0,4) != "TRCE") return 1;
            count = static_cast<uint8_t>(sim.uart.bytes[4]) |
                    (static_cast<uint8_t>(sim.uart.bytes[5]) << 8);
            if (!count || count > 256) return 1;
            expected = 6 + count*17;
        }
        if (expected && sim.uart.bytes.size() == expected) {
            for (unsigned j = 0; j < 1000; ++j) sim.step();
            if (sim.uart.bytes.size() != expected || !sim.dut.uart_tx) return 1;
            std::printf("PASS: shared UART diagnostic packet (%u records), complete final stop bit\n", count);
            sim.dut.final(); return 0;
        }
    }
    return 1;
}
