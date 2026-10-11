#include "Vprivileged_core_sim.h"
#include "verilated.h"
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

constexpr int kClocksPerBit = 432;
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
    Vprivileged_core_sim dut;
    UartReceiver uart;
    uint64_t order = 0, ticks = 0;
    unsigned core_half = 5, mig_half = 7;
    Simulator() {
        if (const char* value = std::getenv("CORE_HALF")) core_half = std::strtoul(value, nullptr, 10);
        if (const char* value = std::getenv("MIG_HALF")) mig_half = std::strtoul(value, nullptr, 10);
        if (!core_half || !mig_half) std::exit(2);
        dut.mig_calib_complete = 0;
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
                dut.retire_insn, dut.retire_priv, dut.retire_rd, dut.retire_rd_data,
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
    if (argc == 2 && std::strcmp(argv[1], "--opensbi") == 0) {
        std::setvbuf(stdout, nullptr, _IONBF, 0);
        unsigned traps = 0;
        const bool diagnostics = std::getenv("BOOT_DIAGNOSTICS");
        size_t shown = 0;
        bool payload_pass = false;
        for (unsigned i = 0; i < 100000000; ++i) {
            sim.step();
            if (sim.dut.retire_valid && sim.dut.retire_trap && ++traps <= 40 && diagnostics)
                std::fprintf(stderr, "probe/trap PC=%08x cause=%08x tval=%08x\n", sim.dut.retire_pc,
                    sim.dut.retire_cause, sim.dut.retire_tval);
            if (diagnostics && i && i % 10000000 == 0)
                std::fprintf(stderr, "boot cycles=%u PC=%08x\n", i, sim.dut.retire_pc);
            while (shown < sim.uart.bytes.size()) std::putchar(sim.uart.bytes[shown++]);
            if (sim.dut.retire_valid && sim.dut.retire_pc >= 0x80040000 && sim.dut.retire_pc < 0x80050000 &&
                sim.dut.retire_rd == 31 && sim.dut.retire_rd_data == 0x600d) payload_pass = true;
            if (payload_pass && !sim.uart.bytes.empty() && sim.uart.bytes.back() == '\n') {
                std::string console(sim.uart.bytes.begin(), sim.uart.bytes.end());
                if (console.find("CHECKPOINT10 SBI TIMER/PMP PASS") == std::string::npos) continue;
                if (console.find("OpenSBI v1.7") == std::string::npos) return 1;
                std::puts("PASS: generic OpenSBI v1.7 entered S payload; SBI BASE, timer interrupt and resident PMP isolation");
                return 0;
            }
            if (sim.dut.retire_valid && sim.dut.retire_pc >= 0x80040000 && sim.dut.retire_pc < 0x80050000 &&
                sim.dut.retire_rd == 31 && sim.dut.retire_rd_data == 0xbad) {
                sim.print_event(); return 1;
            }
            if (sim.dut.done) return 1;
        }
        std::fprintf(stderr, "OpenSBI watchdog last PC=%08x\n", sim.dut.retire_pc);
        return 1;
    }
    if (argc == 2 && std::strcmp(argv[1], "--fatal-fence") == 0) {
        unsigned retired = 0;
        for (unsigned i = 0; i < 20000; ++i) {
            sim.step();
            if (sim.dut.retire_valid) {
                if (retired >= 4 || sim.dut.retire_pc != 0x80000000u + 4 * retired) return 1;
                if (retired == 3 && (!sim.dut.retire_trap || sim.dut.retire_cause != 7 ||
                    sim.dut.retire_tval != sim.dut.retire_pc)) return 1;
                ++retired;
            }
            if (sim.dut.done) {
                if (retired != 4) return 1;
                std::puts("PASS: failed FENCE.I writeback remains fail-stop with privilege enabled");
                return 0;
            }
        }
        return 1;
    }
    if (argc == 2 && std::strcmp(argv[1], "--run") == 0) {
        for (unsigned i = 0; i < 200000; ++i) {
            sim.step();
            if (sim.dut.retire_valid && sim.dut.retire_trap)
                std::printf("trap priv=%u pc=%08x cause=%08x tval=%08x\n", sim.dut.retire_priv,
                    sim.dut.retire_pc, sim.dut.retire_cause, sim.dut.retire_tval);
            if (sim.dut.retire_valid && sim.dut.retire_rd == 31) {
                if (sim.dut.retire_rd_data == 0x600d) {
                    std::puts("PASS: integrated privilege program reached success signature");
                    return 0;
                }
                if (sim.dut.retire_rd_data == 0xbad) { sim.print_event(); return 1; }
            }
            if (sim.dut.done) return 1;
        }
        std::fprintf(stderr, "privilege watchdog last PC=%08x\n", sim.dut.retire_pc);
        return 1;
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
    sim.dut.final();
    return 0;
}
