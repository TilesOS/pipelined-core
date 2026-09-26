`timescale 1ns/1ps
// Integration boundary for checkpoint 8's MIG and checkpoint 9's caches.
// A falling calibration signal aborts in-flight traffic and resets all FIFOs.
// Masters must remain reset until masters_ready is asserted.
module axi_subsystem (
    input logic core_clk,
    input logic mig_clk,
    input logic rst_n,
    input logic mig_calib_complete,
    output logic masters_ready,
    input axi128_pkg::axi_req_t master_req [4],
    output axi128_pkg::axi_rsp_t master_rsp [4],
    output axi128_pkg::axi_req_t peripheral_req,
    input axi128_pkg::axi_rsp_t peripheral_rsp,
    output axi128_pkg::axi_req_t mig_req,
    input axi128_pkg::axi_rsp_t mig_rsp,
    output logic [1:0] read_owner_probe,
    output logic [1:0] write_owner_probe,
    output logic [1:0] active_probe,
    output logic [2:0] aw_level,
    output logic [2:0] w_level,
    output logic [2:0] ar_level,
    output logic [2:0] b_level,
    output logic [2:0] r_level
);
    import axi128_pkg::*;
    logic link_rst_n;
    (* async_reg = "true" *) logic [1:0] core_release;
    axi_req_t slave_req [2];
    axi_rsp_t slave_rsp [2];

    assign link_rst_n = rst_n && mig_calib_complete;
    always_ff @(posedge core_clk or negedge link_rst_n) begin
        if (!link_rst_n) core_release <= '0;
        else core_release <= {core_release[0], 1'b1};
    end
    assign masters_ready = core_release[1];

    axi_fabric fabric (
        .clk(core_clk), .rst_n(masters_ready), .m_req(master_req),
        .m_rsp(master_rsp), .s_req(slave_req), .s_rsp(slave_rsp),
        .read_owner_probe(read_owner_probe),
        .write_owner_probe(write_owner_probe), .active_probe(active_probe)
    );
    axi_cdc crossing (
        .core_clk(core_clk), .mig_clk(mig_clk), .rst_n(link_rst_n),
        .core_req(slave_req[0]), .core_rsp(slave_rsp[0]),
        .mig_req(mig_req), .mig_rsp(mig_rsp), .aw_level(aw_level),
        .w_level(w_level), .ar_level(ar_level), .b_level(b_level),
        .r_level(r_level)
    );
    assign peripheral_req = slave_req[1];
    assign slave_rsp[1] = peripheral_rsp;
endmodule
