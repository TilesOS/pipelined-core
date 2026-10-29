// One PMP access check against the eight pmpcfg/pmpaddr entries.
// PMP is checked before cache lookup and before any device request.
// The first entry overlapping any byte wins, including partial matches.
module rv32_pmp #(
    parameter bit ENABLE_PRIVILEGE = 0
) (
    input  logic [7:0]  pmpcfg [8],
    input  logic [31:0] pmpaddr [8],
    input  logic [31:0] addr,
    input  logic [1:0]  size,
    input  logic [1:0]  mode,
    input  logic        read_access,
    input  logic        write_access,
    input  logic        execute_access,
    output logic        allow
);
    logic [34:0] napot_mask [8];

    for (genvar entry = 0; entry < 8; entry++) begin : napot_masks
        assign napot_mask[entry][2:0] = 3'b111;
        assign napot_mask[entry][34] = 1'b0;
        for (genvar bit_no = 0; bit_no < 31; bit_no++) begin : prefix_bits
            assign napot_mask[entry][bit_no+3] = &pmpaddr[entry][bit_no:0];
        end
    end

    always_comb begin
        logic full_match, start_matches, end_matches;
        logic [7:0] overlaps, grants, selected;
        logic [34:0] low_addr, high_addr, first_byte, last_byte, mask;
        overlaps = 0; grants = 0; selected = 0;
        first_byte = {3'b0, addr}; last_byte = first_byte + (35'd1 << size) - 1;
        for (int i = 0; i < 8; i++) begin
            low_addr = 0; high_addr = 0; mask = 0;
            full_match = 0; start_matches = 0; end_matches = 0;
            case (pmpcfg[i][4:3])
                1: begin // TOR
                    low_addr = i == 0 ? 35'b0 : {1'b0, pmpaddr[i-1], 2'b0};
                    high_addr = {1'b0, pmpaddr[i], 2'b0};
                    overlaps[i] = low_addr < high_addr && first_byte < high_addr && last_byte >= low_addr;
                    full_match = first_byte >= low_addr && last_byte < high_addr;
                end
                2: begin // NA4
                    // NA4 spans exactly one aligned word, including an access
                    // that straddles it with neither endpoint inside it.
                    overlaps[i] = first_byte[34:2] <= {1'b0, pmpaddr[i]} &&
                                  last_byte[34:2] >= {1'b0, pmpaddr[i]};
                    full_match = first_byte[34:2] == {1'b0, pmpaddr[i]} &&
                                 last_byte[34:2] == {1'b0, pmpaddr[i]};
                end
                3: begin // NAPOT
                    // Constant-position prefix bits replace the serial
                    // trailing-one counter, variable shift and range adder.
                    mask = napot_mask[i];
                    low_addr = {1'b0, pmpaddr[i], 2'b0} & ~mask;
                    start_matches = (first_byte & ~mask) == low_addr;
                    end_matches = (last_byte & ~mask) == low_addr;
                    // NAPOT regions are at least eight bytes; every supported
                    // access is at most eight, so overlap hits an endpoint.
                    overlaps[i] = start_matches || end_matches;
                    full_match = start_matches && end_matches;
                end
                default: ;
            endcase
            grants[i] = full_match && ((mode == 3 && !pmpcfg[i][7]) ||
                ((!read_access || pmpcfg[i][0]) && (!write_access || pmpcfg[i][1]) &&
                 (!execute_access || pmpcfg[i][2])));
        end
        for (int i = 0; i < 8; i++)
            selected[i] = overlaps[i] && (overlaps & 8'((1 << i)-1)) == 0;
        allow = !ENABLE_PRIVILEGE || (mode == 3 && overlaps == 0) || |(selected & grants);
    end
endmodule
