// Subordinate-side environment assumptions (one instance per DUT master port S1..S9).
// These constrain the signals a subordinate DRIVES into the interconnect
// (AWREADY/WREADY/BVALID/BRESP/ARREADY/RDATA/RRESP/RVALID).
//
// Section A: legal AXI4-Lite subordinate behaviour (an axi_lite_slave_wrapper
//            style slave: one outstanding write, one outstanding read); always on.
// Section B: optional restrictions, switched on by defines (tool/jg.tcl profiles).
//
//   FV_SUB_NO_STALL  AWREADY/WREADY/ARREADY held high
//   FV_SUB_FAST_RSP  BVALID the cycle after AW and W are accepted, RVALID the
//                    cycle after AR is accepted (no response latency)
//   FV_SUB_NO_ERR    only OKAY responses (no SLVERR)

module fv_sub_assume #(
    parameter int AW = 32,
    parameter int DW = 32
)(
    input logic          clk,
    input logic          rstn,

    // driven by the DUT (observed)
    input logic          awvalid,
    input logic [AW-1:0] awaddr,
    input logic          wvalid,
    input logic [DW-1:0] wdata,
    input logic          bready,
    input logic          arvalid,
    input logic [AW-1:0] araddr,
    input logic          rready,

    // driven by the subordinate (constrained here)
    input logic          awready,
    input logic          wready,
    input logic          bvalid,
    input logic [1:0]    bresp,
    input logic          arready,
    input logic [DW-1:0] rdata,
    input logic [1:0]    rresp,
    input logic          rvalid
);

    default clocking cb @(posedge clk); endclocking
    default disable iff (!rstn);

    localparam logic [1:0] OKAY   = 2'b00;
    localparam logic [1:0] SLVERR = 2'b10;

    // -------------------------------------------------------------------------
    // Section A: legal subordinate behaviour
    // -------------------------------------------------------------------------

    // aw_g / w_g / ar_g: request accepted by this subordinate, response not yet accepted
    logic aw_g, w_g, ar_g;
    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            aw_g <= 1'b0;
            w_g  <= 1'b0;
            ar_g <= 1'b0;
        end
        else begin
            if (awvalid && awready) aw_g <= 1'b1;
            if (wvalid  && wready)  w_g  <= 1'b1;
            if (bvalid  && bready)  begin aw_g <= 1'b0; w_g <= 1'b0; end
            if (arvalid && arready) ar_g <= 1'b1;
            if (rvalid  && rready)  ar_g <= 1'b0;
        end
    end

    // S1: no responses in reset
    s_rst_idle: assume property (@(posedge clk) disable iff (1'b0)
        !rstn |-> !(bvalid || rvalid));

    // S2: responses only after the request was accepted (B needs AW and W)
    s_b_after_req: assume property (bvalid |-> aw_g && w_g);
    s_r_after_req: assume property (rvalid |-> ar_g);

    // S3: VALID held and payload stable until READY
    s_b_hold: assume property (bvalid && !bready |=> bvalid && $stable(bresp));
    s_r_hold: assume property (rvalid && !rready |=> rvalid && $stable(rdata) && $stable(rresp));

    // S4: only OKAY / SLVERR (DECERR comes from the interconnect, EXOKAY unused)
    s_bresp_legal: assume property (bvalid |-> (bresp == OKAY || bresp == SLVERR));
    s_rresp_legal: assume property (rvalid |-> (rresp == OKAY || rresp == SLVERR));

    // -------------------------------------------------------------------------
    // Section B: optional restrictions
    // -------------------------------------------------------------------------

`ifdef FV_SUB_NO_STALL
    s_ready_hi: assume property (awready && wready && arready);
`endif

`ifdef FV_SUB_FAST_RSP
    s_b_fast: assume property (aw_g && w_g |-> bvalid);
    s_r_fast: assume property (ar_g |-> rvalid);
`endif

`ifdef FV_SUB_NO_ERR
    s_bresp_ok: assume property (bvalid |-> bresp == OKAY);
    s_rresp_ok: assume property (rvalid |-> rresp == OKAY);
`endif

endmodule
