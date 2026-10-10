#include "Vcached_core_sim.h"
#include "verilated.h"
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

constexpr int kClocksPerBit = 8;
struct UartReceiver {
    int countdown = -1;
    int bit = 0;
    int previous = 1;
    uint8_t value = 0;
    std::vector<uint8_t> bytes;

    void sample(int tx) {
        if (countdown < 0) {
            if (previous && !tx) {
                countdown = kClocksPerBit + kClocksPerBit / 2;
                bit = 0;
                value = 0;
            }
        } else if (--countdown == 0) {
            if (bit < 8) {
                value |= static_cast<uint8_t>(tx << bit);
                ++bit;
                countdown = kClocksPerBit;
            } else {
                if (tx != 1) {
                    std::fprintf(stderr, "UART framing error\n");
                    std::exit(2);
                }
                bytes.push_back(value);
                countdown = -1;
            }
        }
        previous = tx;
    }
};

struct Simulator {
    Vcached_core_sim dut;
    UartReceiver uart;
    uint64_t order = 0, ticks = 0;
    unsigned core_half = 5, mig_half = 7;
    Simulator() {
        if (const char* value = std::getenv("CORE_HALF")) core_half = std::strtoul(value, nullptr, 10);
        if (const char* value = std::getenv("MIG_HALF")) mig_half = std::strtoul(value, nullptr, 10);
        if (!core_half || !mig_half) std::exit(2);
        dut.dma_test_mode = 0;
        if (const char* value = std::getenv("DMA_TEST_MODE")) dut.dma_test_mode = std::strtoul(value, nullptr, 10);
        dut.hang_memory = 0; dut.mig_calib_complete = 0;
        dut.rst_n = 0; dut.manual_halt = 0; dut.dump_button = 0;
        for (unsigned i = 0; i < 100; ++i) tick();
        dut.rst_n = 1; dut.mig_calib_complete = 1;
    }
    void tick() {
        ++ticks;
        dut.clk = (ticks / core_half) & 1;
        dut.mig_clk = (ticks / mig_half) & 1;
        dut.eval();
    }
    void step() {
        // Exactly one core rising edge per command, regardless of MIG ratio.
        while (dut.clk) tick();
        while (!dut.clk) tick();
        uart.sample(dut.uart_tx);
    }
    void print_event() {
        if (dut.retire_valid) {
            char csr_json[80] = "[]";
            if (dut.retire_csr_write)
                std::snprintf(csr_json, sizeof(csr_json),
                              "[{\"addr\":\"%03x\",\"value\":\"%08x\"}]",
                              dut.retire_csr_addr, dut.retire_csr_data);
            std::printf(
                "{\"kind\":\"retire\",\"order\":%llu,\"pc\":\"%08x\","
                "\"insn\":\"%08x\",\"priv\":%u,\"rd\":%u,"
                "\"rd_data\":\"%08x\",\"mem_addr\":\"%08x\","
                "\"mem_rmask\":%u,\"mem_wmask\":%u,"
                "\"mem_wdata\":\"%08x\",\"trap\":%s,"
                "\"cause\":\"%08x\",\"tval\":\"%08x\","
                "\"csr_writes\":%s}\n",
                static_cast<unsigned long long>(order++), dut.retire_pc,
                dut.retire_insn, 3, dut.retire_rd, dut.retire_rd_data,
                dut.retire_mem_addr, dut.retire_mem_rmask, dut.retire_mem_wmask,
                dut.retire_mem_wdata, dut.retire_trap ? "true" : "false",
                dut.retire_cause, dut.retire_tval, csr_json);
        } else if (dut.done) {
            std::puts("{\"kind\":\"done\"}");
        } else {
            std::puts("{\"kind\":\"cycle\"}");
        }
        std::fflush(stdout);
    }
};
int main(int argc, char** argv) {
    const char* image = std::getenv("CACHE_IMAGE");
    if (!image) { std::fputs("CACHE_IMAGE must name a hex image\n", stderr); return 2; }
    std::vector<std::string> args;
    for (int i = 0; i < argc; ++i) args.emplace_back(argv[i]);
    args.emplace_back(std::string("+image=") + image);
    if (const char* seed = std::getenv("CACHE_SEED")) args.emplace_back(std::string("+seed=") + seed);
    if (const char* address = std::getenv("FAIL_READ_ADDR")) args.emplace_back(std::string("+fail_read_addr=") + address);
    if (const char* address = std::getenv("FAIL_WRITE_ADDR")) args.emplace_back(std::string("+fail_write_addr=") + address);
    std::vector<const char*> pointers;
    for (const auto& arg : args) pointers.push_back(arg.c_str());
    Verilated::commandArgs(pointers.size(), pointers.data());
    Simulator sim;
    if (argc == 2 && std::strcmp(argv[1], "--reset-test") == 0) {
        // Abort an in-flight I refill, then a cache containing a dirty store.
        for (unsigned phase = 0; phase < 2; ++phase) {
            if (phase == 0) {
                while (!sim.dut.masters_ready) sim.step();
                for (unsigned i = 0; i < 5; ++i) sim.step();
            } else {
                bool stored = false;
                for (unsigned i = 0; i < 2000 && !stored; ++i) {
                    sim.step(); stored = sim.dut.retire_valid && sim.dut.retire_mem_wmask;
                }
                if (!stored) return 1;
            }
            sim.dut.mig_calib_complete = 0;
            for (unsigned i = 0; i < 20; ++i) sim.step();
            if (sim.dut.masters_ready || sim.dut.retire_valid) return 1;
            sim.dut.mig_calib_complete = 1;
        }
        unsigned retired = 0;
        for (unsigned i = 0; i < 3000 && retired < 7; ++i) {
            sim.step();
            if (sim.dut.retire_valid) {
                if (sim.dut.retire_pc != 0x80000000u + 4 * retired) return 1;
                if (retired == 4 && sim.dut.retire_rd_data != 12) return 1;
                if (retired == 6 && (!sim.dut.retire_trap || sim.dut.retire_cause != 2)) return 1;
                ++retired;
            }
        }
        if (retired != 7) return 1;
        std::puts("PASS: calibration loss reset an in-flight refill and dirty cache; CPU restarted with seven ordered events");
        return 0;
    }
    if (argc == 2 && std::strcmp(argv[1], "--hang-test") == 0) {
        unsigned retired = 0;
        for (unsigned i = 0; i < 2000 && !retired; ++i) { sim.step(); retired += sim.dut.retire_valid; }
        if (retired != 1) return 1;
        sim.dut.hang_memory = 1;
        for (unsigned i = 0; i < 40; ++i) { sim.step(); if (sim.dut.retire_valid) return 1; }
        sim.dut.dump_button = 1;
        for (unsigned i = 0; i < 10; ++i) sim.step();
        sim.dut.dump_button = 0;
        for (unsigned i = 0; i < 10000 && sim.uart.bytes.size() < 23; ++i) {
            sim.step(); if (sim.dut.retire_valid) return 1;
        }
        const auto& bytes = sim.uart.bytes;
        if (bytes.size() != 23 || std::memcmp(bytes.data(), "TRCE", 4) || bytes[4] != 1 || bytes[5] != 0)
            return 1;
        if (bytes[6] != 0 || bytes[7] != 0 || bytes[8] != 0 || bytes[9] != 0x80) return 1;
        std::puts("PASS: button UART dumped the last retired PC during a hung cache refill");
        return 0;
    }
    char command[32];
    while (std::fgets(command, sizeof(command), stdin)) {
        if (std::strcmp(command, "quit\n") == 0) break;
        if (std::strcmp(command, "step\n") != 0) return 2;
        sim.step();
        sim.print_event();
    }
    std::fprintf(stderr, "Cache traffic: I misses=%u bypass=%u D misses=%u writebacks=%u bypass=%u\n",
        sim.dut.icache_misses, sim.dut.icache_bypasses, sim.dut.dcache_misses,
        sim.dut.dcache_writebacks, sim.dut.dcache_bypasses);
    std::fprintf(stderr, "DMA done=%u blocked=%u\n", sim.dut.dma_write_done, sim.dut.dma_was_blocked);
    sim.dut.final();
    return 0;
}
