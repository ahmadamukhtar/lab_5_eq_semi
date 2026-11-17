// ==============================================================================
// Copyright (c) Empty Quarter Semiconductor Co. - EQSemi
// All rights reserved.
// EQSEMI CONFIDENTIAL -- do not copy, disclose or distribute without written permission.
// ------------------------------------------------------------------------------
// Project       : edge-ai-eqsemi
// File          : verif/uvm/common/axi4l_uvc/axi4l_protocol_checker.sv
// ==============================================================================
// AXI4-Lite protocol checker (SVA), one instance per port (M1, M2, S1..S9).
// Passive: connects to the axi4_lite_if.monitor modport. Failures are reported
// through uvm_report_error, so they are counted in the UVM test result.
//
// MGR_SIDE = 1 : the bus is a manager port of the DUT   (DUT drives AxREADY, B*, R*)
// MGR_SIDE = 0 : the bus is a subordinate port of the DUT (DUT drives AxVALID, W*, BREADY, RREADY)
// The rules are identical on both sides except for the "DUT outputs low in reset" check.
//
// Compile after axi4_lite_if.sv and the UVM library; not part of axi4l_pkg.
// Rule IDs (P-x) refer to SPECS.md section 4.6.

module axi4l_protocol_checker #(
    parameter int    ADDR_WIDTH = 32,
    parameter int    DATA_WIDTH = 32,
    parameter bit    MGR_SIDE   = 1'b1,
    parameter string NAME       = "port"
)(
    axi4_lite_if.monitor bus
);
    import uvm_pkg::*;

    wire clk = bus.ACLK;
    wire rstn = bus.ARESETn;

    function automatic void fail(string rule, string msg);
        uvm_report_error("SVA_PROTO", $sformatf("[%s] %s: %s @%0t", NAME, rule, msg, $time), UVM_NONE);
    endfunction

    default clocking cb @(posedge clk); endclocking
    default disable iff (!rstn);

    // ---- Handshakes and outstanding-transaction state --------------------------------
    wire aw_hs = bus.AWVALID && bus.AWREADY;
    wire w_hs  = bus.WVALID  && bus.WREADY;
    wire b_hs  = bus.BVALID  && bus.BREADY;
    wire ar_hs = bus.ARVALID && bus.ARREADY;
    wire r_hs  = bus.RVALID  && bus.RREADY;

    bit aw_seen, w_seen, ar_seen;   // accepted, response (B/R) not yet accepted

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            aw_seen <= 1'b0;
            w_seen  <= 1'b0;
            ar_seen <= 1'b0;
        end
        else begin
            if (aw_hs) aw_seen <= 1'b1;
            if (w_hs)  w_seen  <= 1'b1;
            if (b_hs) begin aw_seen <= 1'b0; w_seen <= 1'b0; end
            if (ar_hs) ar_seen <= 1'b1;
            if (r_hs)  ar_seen <= 1'b0;
        end
    end

    // Consecutive clocks with reset low (used to skip the first, unsettled reset cycles).
    int unsigned rst_low_cnt;
    always_ff @(posedge clk)
        rst_low_cnt <= rstn ? 0 : (rst_low_cnt + 1);

    // ---- P-1/P-2: VALID held, payload stable until READY -----------------------------
    a_aw_stable: assert property (bus.AWVALID && !bus.AWREADY |=> bus.AWVALID && $stable(bus.AWADDR))
        else fail("P-1/2", "AW: VALID dropped or AWADDR changed before AWREADY");
    a_w_stable:  assert property (bus.WVALID && !bus.WREADY |=> bus.WVALID && $stable(bus.WDATA))
        else fail("P-1/2", "W: VALID dropped or WDATA changed before WREADY");
    a_ar_stable: assert property (bus.ARVALID && !bus.ARREADY |=> bus.ARVALID && $stable(bus.ARADDR))
        else fail("P-1/2", "AR: VALID dropped or ARADDR changed before ARREADY");
    a_b_stable:  assert property (bus.BVALID && !bus.BREADY |=> bus.BVALID && $stable(bus.BRESP))
        else fail("P-1/2", "B: VALID dropped or BRESP changed before BREADY");
    a_r_stable:  assert property (bus.RVALID && !bus.RREADY |=> bus.RVALID && $stable(bus.RDATA) && $stable(bus.RRESP))
        else fail("P-1/2", "R: VALID dropped or RDATA/RRESP changed before RREADY");

    // ---- P-3: no X/Z ------------------------------------------------------------------
    a_ctrl_known: assert property (!$isunknown({bus.AWVALID, bus.AWREADY, bus.WVALID, bus.WREADY,
                                                bus.BVALID, bus.BREADY, bus.ARVALID, bus.ARREADY,
                                                bus.RVALID, bus.RREADY}))
        else fail("P-3", "X/Z on a VALID/READY signal");
    a_aw_known: assert property (bus.AWVALID |-> !$isunknown(bus.AWADDR))
        else fail("P-3", "X/Z on AWADDR while AWVALID");
    a_w_known:  assert property (bus.WVALID |-> !$isunknown(bus.WDATA))
        else fail("P-3", "X/Z on WDATA while WVALID");
    a_ar_known: assert property (bus.ARVALID |-> !$isunknown(bus.ARADDR))
        else fail("P-3", "X/Z on ARADDR while ARVALID");
    a_b_known:  assert property (bus.BVALID |-> !$isunknown(bus.BRESP))
        else fail("P-3", "X/Z on BRESP while BVALID");
    a_r_known:  assert property (bus.RVALID |-> !$isunknown({bus.RDATA, bus.RRESP}))
        else fail("P-3", "X/Z on RDATA/RRESP while RVALID");

    // ---- P-4: EXOKAY is not used ------------------------------------------------------
    a_bresp_legal: assert property (bus.BVALID |-> bus.BRESP != 2'b01)
        else fail("P-4", "BRESP = EXOKAY (01)");
    a_rresp_legal: assert property (bus.RVALID |-> bus.RRESP != 2'b01)
        else fail("P-4", "RRESP = EXOKAY (01)");

    // ---- P-5: one outstanding write and one outstanding read ---------------------------
    a_one_aw: assert property (aw_hs |-> !aw_seen)
        else fail("P-5", "second AW accepted before the B response of the previous write");
    a_one_w:  assert property (w_hs |-> !w_seen)
        else fail("P-5", "second W beat accepted before the B response (duplicate write data)");
    a_one_ar: assert property (ar_hs |-> !ar_seen)
        else fail("P-5", "second AR accepted before the R response of the previous read");

    // ---- Response ordering ---------------------------------------------------------------
    a_b_after_aw_w: assert property (bus.BVALID |-> aw_seen && w_seen)
        else fail("P-6", "BVALID before both AW and W were accepted");
    a_r_after_ar:   assert property (bus.RVALID |-> ar_seen)
        else fail("P-6", "RVALID before AR was accepted");

    // ---- Reset: DUT-driven handshake signals are low while in reset ----------------------
    generate
        if (MGR_SIDE) begin : g_rst_mgr
            a_rst_outputs: assert property (@(posedge clk) disable iff (1'b0)
                (!rstn && rst_low_cnt >= 2) |->
                    !(bus.AWREADY || bus.WREADY || bus.BVALID || bus.ARREADY || bus.RVALID))
                else fail("F-RST-1", "DUT drives READY/VALID high during reset");
        end
        else begin : g_rst_sub
            a_rst_outputs: assert property (@(posedge clk) disable iff (1'b0)
                (!rstn && rst_low_cnt >= 2) |->
                    !(bus.AWVALID || bus.WVALID || bus.BREADY || bus.ARVALID || bus.RREADY))
                else fail("F-RST-1", "DUT drives VALID/READY high during reset");
        end
    endgenerate
endmodule
