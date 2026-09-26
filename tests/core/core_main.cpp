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
        dut.external_store_valid = 0;
        dut.external_store_addr = 0;
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

int reservation_case(const char* image, int external_kind, int expected_status,
                     uint32_t expected_word) {
    Simulator sim(image);
    bool inject = false;
    bool saw_sc = false;
    bool saw_load = false;
    for (unsigned cycle = 0; cycle < 500; ++cycle) {
        if (inject) {
            const uint32_t interference = kBase + 0x1000u +
                                          (external_kind == 2 ? 4u : 0u);
            const unsigned offset = interference - kBase;
            sim.memory[offset] = 9;
            sim.memory[offset + 1] = 0;
            sim.memory[offset + 2] = 0;
            sim.memory[offset + 3] = 0;
            sim.dut.external_store_valid = 1;
            sim.dut.external_store_addr = interference;
            inject = false;
        }
        sim.step();
        sim.dut.external_store_valid = 0;
        if (sim.dut.retire_valid) {
            if (sim.dut.retire_pc == kBase + 12 && external_kind)
                inject = true; // interfere just after LR retirement
            if (sim.dut.retire_pc == kBase + 20) {
                saw_sc = true;
                if (sim.dut.retire_rd != 5 ||
                    sim.dut.retire_rd_data != static_cast<uint32_t>(expected_status)) {
                    std::fprintf(stderr, "wrong SC status under contention\n");
                    return 1;
                }
            }
            if (sim.dut.retire_pc == kBase + 24) {
                saw_load = true;
                if (sim.dut.retire_rd != 6 || sim.dut.retire_rd_data != expected_word) {
                    std::fprintf(stderr, "wrong load after contention\n");
                    return 1;
                }
            }
        }
        if (sim.dut.done) break;
    }
    if (!saw_sc || !saw_load || sim.word(kBase + 0x1000u) != expected_word) {
        std::fprintf(stderr, "reservation case did not finish with expected memory\n");
        return 1;
    }
    return 0;
}

int counter_test(Simulator& sim) {
    bool saw_instret = false;
    bool saw_cycle_first = false;
    bool saw_cycle_second = false;
    bool saw_cycle_write = false;
    bool saw_cycle_high = false;
    bool saw_instret_high = false;
    uint32_t cycle_first = 0;
    uint32_t cycle_second = 0;
    for (unsigned cycle = 0; cycle < 500; ++cycle) {
        sim.step();
        if (sim.dut.retire_valid) {
            if (sim.dut.retire_pc == kBase + 8) {
                saw_instret = true;
                if (sim.dut.retire_rd != 2 || sim.dut.retire_rd_data != 20) {
                    std::fprintf(stderr, "minstret write/read ordering failed\n");
                    return 1;
                }
            }
            if (sim.dut.retire_pc == kBase + 16) {
                saw_cycle_first = true;
                cycle_first = sim.dut.retire_rd_data;
            }
            if (sim.dut.retire_pc == kBase + 20) {
                saw_cycle_second = true;
                cycle_second = sim.dut.retire_rd_data;
            }
            if (sim.dut.retire_pc == kBase + 32) {
                saw_cycle_write = true;
                if (sim.dut.retire_rd_data < 100 || sim.dut.retire_rd_data >= 200)
                    return 1;
            }
            if (sim.dut.retire_pc == kBase + 44) {
                saw_cycle_high = true;
                if (sim.dut.retire_rd_data != 1) return 1;
            }
            if (sim.dut.retire_pc == kBase + 52) {
                saw_instret_high = true;
                if (sim.dut.retire_rd_data != 1) return 1;
            }
        }
        if (sim.dut.done) break;
    }
    if (!saw_instret || !saw_cycle_first || !saw_cycle_second ||
        !saw_cycle_write || !saw_cycle_high || !saw_instret_high ||
        cycle_second <= cycle_first) {
        std::fprintf(stderr, "machine counters did not advance as expected\n");
        return 1;
    }
    std::puts("PASS: 64-bit mcycle/minstret halves, write/read order, and monotonic cycles");
    return 0;
}

int amo_contention_test(Simulator& sim) {
    bool saw_lock = false;
    bool saw_amo = false;
    bool injected = false;
    bool saw_load = false;
    for (unsigned cycle = 0; cycle < 500; ++cycle) {
        if (saw_lock && saw_amo && !injected && !sim.dut.atomic_lock) {
            sim.memory[0x1000] = 9;
            sim.memory[0x1001] = 0;
            sim.memory[0x1002] = 0;
            sim.memory[0x1003] = 0;
            sim.dut.external_store_valid = 1;
            sim.dut.external_store_addr = kBase + 0x1000u;
            injected = true;
        }
        sim.step();
        sim.dut.external_store_valid = 0;
        saw_lock |= sim.dut.atomic_lock;
        if (sim.dut.retire_valid && sim.dut.retire_pc == kBase + 12) {
            saw_amo = true;
            if (sim.dut.retire_rd != 3 || sim.dut.retire_rd_data != 5 ||
                sim.word(kBase + 0x1000u) != 10) {
                std::fprintf(stderr, "AMO did not commit before competing store\n");
                return 1;
            }
        }
        if (saw_lock && !saw_amo && !sim.dut.atomic_lock) {
            std::fprintf(stderr, "AMO lock released before retirement\n");
            return 1;
        }
        if (sim.dut.retire_valid && sim.dut.retire_pc == kBase + 16) {
            saw_load = true;
            if (sim.dut.retire_rd != 4 || sim.dut.retire_rd_data != 9) {
                std::fprintf(stderr, "post-AMO load missed competing store\n");
                return 1;
            }
        }
        if (sim.dut.done) break;
    }
    if (!saw_lock || !saw_amo || !injected || !saw_load ||
        sim.word(kBase + 0x1000u) != 9) {
        std::fprintf(stderr, "AMO contention sequence incomplete\n");
        return 1;
    }
    std::puts("PASS: AMO held memory lock through commit and serialized competing store");
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
    if (argc == 2 && std::strcmp(argv[1], "--contention-test") == 0) {
        if (reservation_case(image, 1, 1, 9) || reservation_case(image, 2, 0, 6))
            return 1;
        std::puts("PASS: competing same-word store invalidated LR; other-word store preserved it");
        return 0;
    }
    if (argc == 2 && std::strcmp(argv[1], "--self-store-test") == 0) {
        if (reservation_case(image, 0, 1, 5)) return 1;
        std::puts("PASS: same-hart conflicting store cleared the reservation");
        return 0;
    }
    if (argc == 2 && std::strcmp(argv[1], "--counter-test") == 0)
        return counter_test(sim);
    if (argc == 2 && std::strcmp(argv[1], "--amo-contention-test") == 0)
        return amo_contention_test(sim);
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
