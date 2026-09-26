#include "Vcheckpoint4_top.h"
#include "verilated.h"

#include <array>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <vector>

namespace {
constexpr uint32_t kBase = 0x80000000u;
constexpr unsigned kMemoryBytes = 65536;
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
    Vcheckpoint4_top dut;
    std::array<uint8_t, kMemoryBytes> memory{};
    UartReceiver uart;
    uint64_t order = 0;

    explicit Simulator(const char* image) {
        std::ifstream file(image, std::ios::binary);
        if (!file) {
            std::fprintf(stderr, "cannot read CORE_IMAGE %s\n", image);
            std::exit(2);
        }
        file.read(reinterpret_cast<char*>(memory.data()), memory.size());
        dut.clk = 0;
        dut.rst_n = 0;
        dut.manual_halt = 0;
        dut.dump_button = 0;
        dut.eval();
        dut.clk = 1;
        dut.eval();
        dut.clk = 0;
        dut.rst_n = 1;
        dut.eval();
    }

    uint32_t word(uint32_t address) const {
        if (address < kBase || address - kBase > kMemoryBytes - 4) return 0xffffffffu;
        const unsigned offset = address - kBase;
        return static_cast<uint32_t>(memory[offset]) |
               (static_cast<uint32_t>(memory[offset + 1]) << 8) |
               (static_cast<uint32_t>(memory[offset + 2]) << 16) |
               (static_cast<uint32_t>(memory[offset + 3]) << 24);
    }

    bool in_range(uint32_t address) const {
        return address >= kBase && address - kBase <= kMemoryBytes - 4;
    }

    void step() {
        dut.clk = 0;
        dut.eval();
        dut.imem_rdata = word(dut.imem_addr);
        dut.imem_fault = !in_range(dut.imem_addr);
        dut.dmem_rdata = word(dut.dmem_addr);
        dut.dmem_fault = !in_range(dut.dmem_addr);
        dut.eval();
        const uint32_t write_address = dut.dmem_waddr;
        const uint32_t write_data = dut.dmem_wdata;
        const uint8_t write_strobes = dut.dmem_wstrb;
        dut.clk = 1;
        dut.eval();
        if (write_strobes) {
            if (write_address < kBase || write_address - kBase > kMemoryBytes - 4) {
                std::fprintf(stderr, "out-of-range data store 0x%08x\n", write_address);
                std::exit(2);
            }
            const unsigned offset = write_address - kBase;
            for (int lane = 0; lane < 4; ++lane)
                if ((write_strobes >> lane) & 1)
                    memory[offset + lane] = static_cast<uint8_t>(write_data >> (8 * lane));
        }
        uart.sample(dut.uart_tx);
    }

    void print_event() {
        if (dut.retire_valid) {
            std::printf(
                "{\"kind\":\"retire\",\"order\":%llu,\"pc\":\"%08x\","
                "\"insn\":\"%08x\",\"priv\":%u,\"rd\":%u,"
                "\"rd_data\":\"%08x\",\"mem_addr\":\"%08x\","
                "\"mem_rmask\":%u,\"mem_wmask\":%u,"
                "\"mem_wdata\":\"%08x\",\"trap\":%s,"
                "\"cause\":\"%08x\",\"tval\":\"%08x\"}\n",
                static_cast<unsigned long long>(order++), dut.retire_pc,
                dut.retire_insn, dut.retire_priv, dut.retire_rd, dut.retire_rd_data,
                dut.retire_mem_addr, dut.retire_mem_rmask, dut.retire_mem_wmask,
                dut.retire_mem_wdata, dut.retire_trap ? "true" : "false",
                dut.retire_cause, dut.retire_tval);
        } else if (dut.done) {
            std::puts("{\"kind\":\"done\"}");
        } else {
            std::puts("{\"kind\":\"cycle\"}");
        }
        std::fflush(stdout);
    }
};

uint32_t read_u32(const std::vector<uint8_t>& bytes, size_t at) {
    return static_cast<uint32_t>(bytes[at]) |
           (static_cast<uint32_t>(bytes[at + 1]) << 8) |
           (static_cast<uint32_t>(bytes[at + 2]) << 16) |
           (static_cast<uint32_t>(bytes[at + 3]) << 24);
}

int hang_test(Simulator& sim) {
    unsigned retired = 0;
    for (unsigned cycle = 0; cycle < 300 && retired < 5; ++cycle) {
        sim.step();
        retired += sim.dut.retire_valid;
    }
    if (retired != 5) {
        std::fprintf(stderr, "core did not retire five instructions before hang\n");
        return 1;
    }
    sim.dut.manual_halt = 1;
    for (int cycle = 0; cycle < 20; ++cycle) sim.step();
    if (sim.dut.trace_count != 5 || sim.dut.retire_valid) {
        std::fprintf(stderr, "trace did not retain five retirements after hang\n");
        return 1;
    }
    sim.dut.dump_button = 1;
    for (int cycle = 0; cycle < 10; ++cycle) sim.step();
    sim.dut.dump_button = 0;
    bool observed_busy = false;
    for (int cycle = 0; cycle < 20000; ++cycle) {
        sim.step();
        if (sim.dut.retire_valid) {
            std::fprintf(stderr, "core retired during forced hang\n");
            return 1;
        }
        observed_busy |= sim.dut.dump_busy;
        if (observed_busy && !sim.dut.dump_busy && sim.uart.bytes.size() >= 91) break;
    }
    const auto& bytes = sim.uart.bytes;
    if (!observed_busy || bytes.size() != 91 ||
        std::memcmp(bytes.data(), "TRCE", 4) != 0 ||
        bytes[4] != 5 || bytes[5] != 0) {
        std::fprintf(stderr, "bad UART dump: busy=%d bytes=%zu\n",
                     observed_busy, bytes.size());
        return 1;
    }
    for (unsigned i = 0; i < 5; ++i) {
        const size_t offset = 6 + i * 17;
        if (read_u32(bytes, offset) != kBase + 4 * i ||
            read_u32(bytes, offset + 4) != sim.word(kBase + 4 * i) ||
            read_u32(bytes, offset + 8) != 0 ||
            read_u32(bytes, offset + 12) != 0 || bytes[offset + 16] != 3) {
            std::fprintf(stderr, "bad trace record %u\n", i);
            return 1;
        }
    }
    if (const char* capture = std::getenv("TRACE_CAPTURE")) {
        std::ofstream output(capture, std::ios::binary);
        output.write(reinterpret_cast<const char*>(bytes.data()), bytes.size());
        if (!output) {
            std::fprintf(stderr, "could not write UART capture %s\n", capture);
            return 1;
        }
    }
    std::puts("PASS: forced pipeline hang; button UART dumped five ordered PC/instruction records");
    return 0;
}

int ring_wrap_test(Simulator& sim) {
    unsigned retired = 0;
    for (unsigned cycle = 0; cycle < 4000 && retired < 300; ++cycle) {
        sim.step();
        retired += sim.dut.retire_valid;
    }
    sim.dut.manual_halt = 1;
    for (int cycle = 0; cycle < 20; ++cycle) sim.step();
    if (retired != 300 || sim.dut.trace_count != 256 ||
        sim.dut.trace_write_ptr != 44) {
        std::fprintf(stderr, "ring did not wrap at 256 entries: retired=%u count=%u ptr=%u\n",
                     retired, sim.dut.trace_count, sim.dut.trace_write_ptr);
        return 1;
    }
    sim.dut.dump_button = 1;
    for (int cycle = 0; cycle < 10; ++cycle) sim.step();
    sim.dut.dump_button = 0;
    constexpr size_t expected = 6 + 256 * 17;
    bool observed_busy = false;
    for (int cycle = 0; cycle < 500000; ++cycle) {
        sim.step();
        observed_busy |= sim.dut.dump_busy;
        if (observed_busy && !sim.dut.dump_busy && sim.uart.bytes.size() >= expected) break;
    }
    const auto& bytes = sim.uart.bytes;
    if (!observed_busy || bytes.size() != expected ||
        std::memcmp(bytes.data(), "TRCE", 4) != 0 ||
        bytes[4] != 0 || bytes[5] != 1) {
        std::fprintf(stderr, "bad wrapped UART dump: busy=%d bytes=%zu\n",
                     observed_busy, bytes.size());
        return 1;
    }
    for (unsigned i = 0; i < 256; ++i) {
        const size_t offset = 6 + i * 17;
        // The first retained event has order 44, so a three-PC loop makes
        // an off-by-one or oldest-entry error visible in the packet.
        const uint32_t pc = kBase + 4 * ((44 + i) % 3);
        if (read_u32(bytes, offset) != pc ||
            read_u32(bytes, offset + 4) != sim.word(pc) ||
            bytes[offset + 16] != 3) {
            std::fprintf(stderr, "wrapped trace record %u corrupt\n", i);
            return 1;
        }
    }
    std::puts("PASS: 256-entry trace ring retained newest 256 of 300 retirements in UART order");
    return 0;
}
} // namespace

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    const char* image = std::getenv("CORE_IMAGE");
    if (!image) {
        std::fprintf(stderr, "CORE_IMAGE must point to the smoke binary\n");
        return 2;
    }
    Simulator sim(image);
    if (argc == 2 && std::strcmp(argv[1], "--hang-test") == 0)
        return hang_test(sim);
    if (argc == 2 && std::strcmp(argv[1], "--ring-test") == 0)
        return ring_wrap_test(sim);
    char command[32];
    while (std::fgets(command, sizeof(command), stdin)) {
        if (std::strcmp(command, "quit\n") == 0) break;
        if (std::strcmp(command, "step\n") != 0) return 2;
        sim.step();
        sim.print_event();
    }
    sim.dut.final();
    return 0;
}
