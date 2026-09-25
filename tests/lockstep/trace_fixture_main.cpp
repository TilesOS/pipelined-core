#include "Vtrace_fixture.h"
#include "verilated.h"

#include <cstdint>
#include <cstdio>
#include <cstring>

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Vtrace_fixture dut;
    dut.clk = 0;
    dut.rst_n = 0;
    dut.eval();
    dut.clk = 1;
    dut.eval();
    dut.clk = 0;
    dut.rst_n = 1;
    dut.eval();

    char command[32];
    uint64_t order = 0;
    while (std::fgets(command, sizeof(command), stdin)) {
        if (std::strcmp(command, "quit\n") == 0) break;
        if (std::strcmp(command, "step\n") != 0) return 2;
        dut.clk = 1;
        dut.eval();
        if (dut.retire_valid) {
            std::printf(
                "{\"kind\":\"retire\",\"order\":%llu,\"pc\":\"%08x\","
                "\"insn\":\"%08x\",\"priv\":%u,\"rd\":%u,"
                "\"rd_data\":\"%08x\",\"mem_addr\":\"%08x\","
                "\"mem_rmask\":%u,\"mem_wmask\":%u,"
                "\"mem_wdata\":\"%08x\",\"trap\":%s,"
                "\"cause\":\"%08x\",\"tval\":\"%08x\"}\n",
                static_cast<unsigned long long>(order++),
                dut.retire_pc, dut.retire_insn, dut.retire_priv, dut.retire_rd,
                dut.retire_rd_data, dut.retire_mem_addr, dut.retire_mem_rmask,
                dut.retire_mem_wmask, dut.retire_mem_wdata,
                dut.retire_trap ? "true" : "false", dut.retire_cause,
                dut.retire_tval);
        } else if (dut.done) {
            std::puts("{\"kind\":\"done\"}");
        } else {
            std::puts("{\"kind\":\"cycle\"}");
        }
        std::fflush(stdout);
        dut.clk = 0;
        dut.eval();
    }
    dut.final();
    return 0;
}
