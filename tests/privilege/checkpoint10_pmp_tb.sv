// Exercise the real core checker against an independent numeric interval model.
module checkpoint10_pmp_tb;
    int checks = 0;
    int seed = 32'h1cf0abcd;
    logic [31:0] address;
    logic [1:0] mode;
    logic [2:0] accesses;
    longint unsigned region_low, region_high, encoded;
    rv32_slice #(.ENABLE_PRIVILEGE(1)) dut (
        .clk(1'b0),
        .rst_n(1'b1),
        .debug_halt(1'b0),
        .msip_irq(1'b0),
        .mtip_irq(1'b0),
        .meip_irq(1'b0),
        .seip_irq(1'b0),
        .time_value(64'b0),
        .imem_protection_fault(),
        .imem_addr(),
        .imem_rdata(32'b0),
        .imem_fault(1'b0),
        .imem_ready(1'b0),
        .imem_valid(),
        .imem_accept(),
        .dmem_ready(1'b0),
        .dstore_ready(1'b0),
        .dstore_fault(1'b0),
        .dmem_read_valid(),
        .dmem_read_accept(),
        .dmem_req_addr(),
        .dmem_size(),
        .dmem_write_valid(),
        .dmem_write_addr(),
        .dmem_write_size(),
        .fence_i_valid(),
        .fence_i_ready(1'b0),
        .fence_i_fault(1'b0),
        .dmem_addr(),
        .dmem_rdata(32'b0),
        .dmem_fault(1'b0),
        .external_store_valid(1'b0),
        .external_store_addr(32'b0),
        .external_store_word_mask(4'b0),
        .atomic_memory_ready(1'b0),
        .atomic_lock(),
        .dmem_waddr(),
        .dmem_wdata(),
        .dmem_wstrb(),
        .retire_valid(),
        .retire_pc(),
        .retire_insn(),
        .retire_priv(),
        .retire_rd(),
        .retire_rd_data(),
        .retire_mem_addr(),
        .retire_mem_rmask(),
        .retire_mem_wmask(),
        .retire_mem_wdata(),
        .retire_trap(),
        .retire_cause(),
        .retire_tval(),
        .retire_csr_write(),
        .retire_csr_addr(),
        .retire_csr_data(),
        .done(),
        .ila_pipeline()
    );
    function automatic logic reference_allow(input logic [31:0] addr,
        input logic [1:0] size, privilege_mode, input logic [2:0] permissions);
        longint unsigned lower, upper, start_byte, end_byte, length, shifted;
        int ones;
        start_byte = 64'(addr);
        end_byte = start_byte + (64'd1 << size);
        for (int entry = 0; entry < 8; entry++) begin
            lower = 0; upper = 0; length = 0;
            shifted = 64'(dut.pmpaddr[entry]);
            case (dut.pmpcfg[entry][4:3])
                1: begin
                    lower = entry == 0 ? 0 : 64'(dut.pmpaddr[entry-1]) * 4;
                    upper = shifted * 4;
                end
                2: begin lower = shifted * 4; upper = lower + 4; end
                3: begin
                    ones = 0;
                    while (ones < 32 && (shifted & 1) != 0) begin
                        ones++; shifted >>= 1;
                    end
                    length = 64'd1 << (ones >= 31 ? 34 : ones + 3);
                    lower = (64'(dut.pmpaddr[entry]) * 4) / length * length;
                    upper = lower + length;
                end
                default: ;
            endcase
            if (lower < upper && start_byte < upper && end_byte > lower)
                return start_byte >= lower && end_byte <= upper &&
                    ((privilege_mode == 3 && !dut.pmpcfg[entry][7]) ||
                     (dut.pmpcfg[entry][2:0] & permissions) == permissions);
        end
        return privilege_mode == 3;
    endfunction
    task automatic check(input logic [31:0] addr, input logic [1:0] size,
        privilege_mode, input logic [2:0] permissions);
        logic expected, actual;
        // Allow generated NAPOT mask wires to settle after test CSR updates.
        #1;
        expected = reference_allow(addr, size, privilege_mode, permissions);
        actual = dut.pmp_allow(addr, size, privilege_mode,
            permissions[0], permissions[1], permissions[2]);
        if (actual !== expected)
            $fatal(1, "PMP mismatch address=%h size=%d mode=%d permissions=%h expected=%d actual=%d",
                addr, size, privilege_mode, permissions, expected, actual);
        checks++;
    endtask
    task automatic clear_entries();
        for (int entry = 0; entry < 8; entry++) begin
            dut.pmpcfg[entry] = 0; dut.pmpaddr[entry] = 0;
        end
    endtask
    initial begin
        void'($urandom(seed));
        clear_entries();
        // Every NAPOT size, including 31/32 trailing ones and full RV32 space.
        for (int ones = 0; ones <= 32; ones++) begin
            encoded = (64'h20001000 & ~((64'd1 << (ones+1))-1)) | ((64'd1 << ones)-1);
            region_low = encoded * 4 / (64'd1 << (ones >= 31 ? 34 : ones+3)) *
                (64'd1 << (ones >= 31 ? 34 : ones+3));
            region_high = region_low + (64'd1 << (ones >= 31 ? 34 : ones+3));
            dut.pmpaddr[0] = 32'(encoded);
            for (int cfg = 0; cfg < 16; cfg++) begin
                dut.pmpcfg[0] = 8'h18 | 8'(cfg & 7) | (cfg >= 8 ? 8'h80 : 8'h0);
                for (int size = 0; size < 4; size++) begin
                    for (int offset = -8; offset <= 8; offset++) begin
                        check(32'(region_low + 64'(offset)), 2'(size), 1, 1);
                        check(32'(region_high + 64'(offset)), 2'(size), 3, 3);
                    end
                    check(32'hffff_fffc, 2'(size), 1, 4);
                end
            end
        end
        // Small overlapping NA4/TOR/NAPOT regions and first-entry precedence.
        for (int kind = 1; kind <= 3; kind++) begin
            clear_entries();
            dut.pmpaddr[0] = 32'h20001002;
            dut.pmpaddr[1] = 32'h20001003;
            dut.pmpcfg[0] = (8'(kind) << 3) | 8'h80;
            dut.pmpcfg[1] = 8'h1f;
            for (int offset = -12; offset <= 24; offset++) begin
                for (int size = 0; size < 4; size++) begin
                    check(32'h80004000 + 32'(offset), 2'(size), 3, 1);
                    check(32'h80004000 + 32'(offset), 2'(size), 1, 3);
                end
            end
        end
        // Random mixed entries, locked/unlocked, reversed/empty TOR and
        // access ranges around each entry as well as arbitrary addresses.
        for (int trial = 0; trial < 2000; trial++) begin
            for (int entry = 0; entry < 8; entry++) begin
                dut.pmpaddr[entry] = trial % 2 == 0 ? 32'h20001000 + ($urandom() & 32'h1f) : $urandom();
                dut.pmpcfg[entry] = 8'($urandom()) & 8'h9f;
            end
            for (int probe = 0; probe < 16; probe++) begin
                address = probe < 8 ? (dut.pmpaddr[probe] << 2) + ($urandom() & 32'hf) - 8 : $urandom();
                mode = 2'($urandom_range(0, 2));
                if (mode == 2) mode = 3;
                accesses = 3'($urandom_range(1, 7));
                check(address, 2'($urandom()), mode, accesses);
            end
        end
        $display("PASS: %0d PMP interval-reference checks (all NAPOT sizes, overlap, boundaries, priority and modes)", checks);
        $finish;
    end
endmodule
