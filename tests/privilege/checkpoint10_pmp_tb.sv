// Exercise the real core checker against an independent numeric interval model.
module checkpoint10_pmp_tb;
    int checks = 0;
    int seed = 32'h1cf0abcd;
    logic [31:0] address;
    logic [1:0] mode;
    logic [2:0] accesses;
    longint unsigned region_low, region_high, encoded;
    logic [7:0] pmpcfg [8];
    logic [31:0] pmpaddr [8];
    logic [31:0] probe_addr;
    logic [1:0] probe_size, probe_mode;
    logic [2:0] probe_permissions;
    logic allow;
    rv32_pmp #(.ENABLE_PRIVILEGE(1)) dut (
        .pmpcfg(pmpcfg),
        .pmpaddr(pmpaddr),
        .addr(probe_addr),
        .size(probe_size),
        .mode(probe_mode),
        .read_access(probe_permissions[0]),
        .write_access(probe_permissions[1]),
        .execute_access(probe_permissions[2]),
        .allow(allow)
    );
    function automatic logic reference_allow(input logic [31:0] addr,
        input logic [1:0] size, privilege_mode, input logic [2:0] permissions);
        longint unsigned lower, upper, start_byte, end_byte, length, shifted;
        int ones;
        start_byte = 64'(addr);
        end_byte = start_byte + (64'd1 << size);
        for (int entry = 0; entry < 8; entry++) begin
            lower = 0; upper = 0; length = 0;
            shifted = 64'(pmpaddr[entry]);
            case (pmpcfg[entry][4:3])
                1: begin
                    lower = entry == 0 ? 0 : 64'(pmpaddr[entry-1]) * 4;
                    upper = shifted * 4;
                end
                2: begin lower = shifted * 4; upper = lower + 4; end
                3: begin
                    ones = 0;
                    while (ones < 32 && (shifted & 1) != 0) begin
                        ones++; shifted >>= 1;
                    end
                    length = 64'd1 << (ones >= 31 ? 34 : ones + 3);
                    lower = (64'(pmpaddr[entry]) * 4) / length * length;
                    upper = lower + length;
                end
                default: ;
            endcase
            if (lower < upper && start_byte < upper && end_byte > lower)
                return start_byte >= lower && end_byte <= upper &&
                    ((privilege_mode == 3 && !pmpcfg[entry][7]) ||
                     (pmpcfg[entry][2:0] & permissions) == permissions);
        end
        return privilege_mode == 3;
    endfunction
    task automatic check(input logic [31:0] addr, input logic [1:0] size,
        privilege_mode, input logic [2:0] permissions);
        logic expected;
        probe_addr = addr;
        probe_size = size;
        probe_mode = privilege_mode;
        probe_permissions = permissions;
        #1;
        expected = reference_allow(addr, size, privilege_mode, permissions);
        if (allow !== expected)
            $fatal(1, "PMP mismatch address=%h size=%d mode=%d permissions=%h expected=%d actual=%d",
                addr, size, privilege_mode, permissions, expected, allow);
        checks++;
    endtask
    task automatic clear_entries();
        for (int entry = 0; entry < 8; entry++) begin
            pmpcfg[entry] = 0; pmpaddr[entry] = 0;
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
            pmpaddr[0] = 32'(encoded);
            for (int cfg = 0; cfg < 16; cfg++) begin
                pmpcfg[0] = 8'h18 | 8'(cfg & 7) | (cfg >= 8 ? 8'h80 : 8'h0);
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
            pmpaddr[0] = 32'h20001002;
            pmpaddr[1] = 32'h20001003;
            pmpcfg[0] = (8'(kind) << 3) | 8'h80;
            pmpcfg[1] = 8'h1f;
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
                pmpaddr[entry] = trial % 2 == 0 ? 32'h20001000 + ($urandom() & 32'h1f) : $urandom();
                pmpcfg[entry] = 8'($urandom()) & 8'h9f;
            end
            for (int probe = 0; probe < 16; probe++) begin
                address = probe < 8 ? (pmpaddr[probe] << 2) + ($urandom() & 32'hf) - 8 : $urandom();
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
