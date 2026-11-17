// Manager-side environment assumptions (one instance per DUT slave port M1, M2).
// These constrain the signals a manager DRIVES into the interconnect
// (AWVALID/AWADDR/WVALID/WDATA/BREADY/ARVALID/ARADDR/RREADY).
//
// Section A: legal AXI4-Lite manager behaviour; always on.
// Section B: optional restrictions to make proofs smaller/faster; each is
//            switched on by a define (see tool/jg.tcl profiles).
//
//   FV_ONE_MGR      handled in fv_ic_top (M2 disabled: EN_WR = EN_RD = 0)
//   FV_NO_WRITE     handled in fv_ic_top (EN_WR = 0, only reads)
//   FV_NO_READ      handled in fv_ic_top (EN_RD = 0, only writes)
//   FV_MAPPED_ONLY  every address decodes to a subordinate
//   FV_UNMAPPED_ONLY every address is a decode miss (DECERR)
//   FV_ONE_TARGET   every address decodes to subordinate FV_DEST_IDX (default 0)
//   FV_ALIGNED      word-aligned addresses
//   FV_MGR_RSP_READY BREADY and RREADY held high (no manager back-pressure)
//   FV_W_WITH_AW    WVALID only while AWVALID or after AW was accepted

`ifndef FV_DEST_IDX
`define FV_DEST_IDX 0
`endif

module fv_mgr_assume
    import fv_ic_pkg::*;
#(
    parameter int AW    = 32,
    parameter int DW    = 32,
    parameter bit EN_WR = 1'b1,
    parameter bit EN_RD = 1'b1
)(
    input logic          clk,
    input logic          rstn,

    // driven by the manager (constrained here)
    input logic          awvalid,
    input logic [AW-1:0] awaddr,
    input logic          wvalid,
    input logic [DW-1:0] wdata,
    input logic          bready,
    input logic          arvalid,
    input logic [AW-1:0] araddr,
    input logic          rready,

    // driven by the DUT (observed)
    input logic          awready,
    input logic          wready,
    input logic          bvalid,
    input logic          arready,
    input logic          rvalid
);

    default clocking cb @(posedge clk); endclocking
    default disable iff (!rstn);

    // -------------------------------------------------------------------------
    // Section A: legal manager behaviour
    // -------------------------------------------------------------------------

    // A1: no requests during reset
    m_rst_idle: assume property (@(posedge clk) disable iff (1'b0)
        !rstn |-> !(awvalid || wvalid || arvalid));

    // A2: VALID stays high and the payload stays stable until READY
    m_aw_hold: assume property (awvalid && !awready |=> awvalid && $stable(awaddr));
    m_w_hold:  assume property (wvalid  && !wready  |=> wvalid  && $stable(wdata));
    m_ar_hold: assume property (arvalid && !arready |=> arvalid && $stable(araddr));

    // A3: one outstanding write and one outstanding read per manager.
    //     aw_d / w_d / ar_d: request accepted, response not yet accepted.
    logic aw_d, w_d, ar_d;
    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            aw_d <= 1'b0;
            w_d  <= 1'b0;
            ar_d <= 1'b0;
        end
        else begin
            if (awvalid && awready) aw_d <= 1'b1;
            if (wvalid  && wready)  w_d  <= 1'b1;
            if (bvalid  && bready)  begin aw_d <= 1'b0; w_d <= 1'b0; end
            if (arvalid && arready) ar_d <= 1'b1;
            if (rvalid  && rready)  ar_d <= 1'b0;
        end
    end

    m_one_aw: assume property (aw_d |-> !awvalid);
    m_one_w:  assume property (w_d  |-> !wvalid);
    m_one_ar: assume property (ar_d |-> !arvalid);

    // -------------------------------------------------------------------------
    // Section B: optional restrictions
    // -------------------------------------------------------------------------

    generate
        if (!EN_WR) begin : g_no_wr
            m_no_wr: assume property (@(posedge clk) !awvalid && !wvalid);
        end
        if (!EN_RD) begin : g_no_rd
            m_no_rd: assume property (@(posedge clk) !arvalid);
        end
    endgenerate

`ifdef FV_MAPPED_ONLY
    m_aw_mapped: assume property (awvalid |-> fv_dec(awaddr) != 4'hF);
    m_ar_mapped: assume property (arvalid |-> fv_dec(araddr) != 4'hF);
`endif

`ifdef FV_UNMAPPED_ONLY
    m_aw_unmapped: assume property (awvalid |-> fv_dec(awaddr) == 4'hF);
    m_ar_unmapped: assume property (arvalid |-> fv_dec(araddr) == 4'hF);
`endif

`ifdef FV_ONE_TARGET
    m_aw_target: assume property (awvalid |-> fv_dec(awaddr) == 4'(`FV_DEST_IDX));
    m_ar_target: assume property (arvalid |-> fv_dec(araddr) == 4'(`FV_DEST_IDX));
`endif

`ifdef FV_ALIGNED
    m_aw_aligned: assume property (awaddr[1:0] == 2'b00);
    m_ar_aligned: assume property (araddr[1:0] == 2'b00);
`endif

`ifdef FV_MGR_RSP_READY
    m_bready_hi: assume property (bready);
    m_rready_hi: assume property (rready);
`endif

`ifdef FV_W_WITH_AW
    m_w_after_aw: assume property (wvalid |-> awvalid || aw_d);
`endif

endmodule
