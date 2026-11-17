// Interconnect-level arbitration checker (SVA, boundary signals only).
//
// Model of the spec (SPECS.md section 4.4), one instance per interconnect, separate per direction:
//   * idle -> busy at the first clock edge where any manager raises AWVALID (ARVALID);
//     owner = M1 if M1 requests, otherwise M2   (M1 has priority)
//   * busy -> idle when the owner's B (R) handshake completes
//   * while busy, the non-owner manager sees no AWREADY/WREADY/BVALID (ARREADY/RVALID): grant lock
//   * while idle, no manager sees AWREADY/BVALID (ARREADY/RVALID)
// Reports through uvm_report_error.

module axi_ic_sva_checker (
    axi4_lite_if.monitor M1,
    axi4_lite_if.monitor M2
);
    import uvm_pkg::*;

    wire clk  = M1.ACLK;
    wire rstn = M1.ARESETn;

    function automatic void fail(string rule, string msg);
        uvm_report_error("SVA_ARB", $sformatf("%s: %s @%0t", rule, msg, $time), UVM_NONE);
    endfunction

    // ---- write direction ---------------------------------------------------
    bit wr_busy, wr_owner;      // owner: 0 = M1, 1 = M2
    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            wr_busy  <= 1'b0;
            wr_owner <= 1'b0;
        end
        else if (!wr_busy && (M1.AWVALID || M2.AWVALID)) begin
            wr_busy  <= 1'b1;
            wr_owner <= !M1.AWVALID;
        end
        else if (wr_busy && (wr_owner ? (M2.BVALID && M2.BREADY) : (M1.BVALID && M1.BREADY)))
            wr_busy  <= 1'b0;
    end

    // ---- read direction ----------------------------------------------------
    bit rd_busy, rd_owner;
    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            rd_busy  <= 1'b0;
            rd_owner <= 1'b0;
        end
        else if (!rd_busy && (M1.ARVALID || M2.ARVALID)) begin
            rd_busy  <= 1'b1;
            rd_owner <= !M1.ARVALID;
        end
        else if (rd_busy && (rd_owner ? (M2.RVALID && M2.RREADY) : (M1.RVALID && M1.RREADY)))
            rd_busy  <= 1'b0;
    end

    default clocking cb @(posedge clk); endclocking
    default disable iff (!rstn);

    // Non-owner sees nothing (covers priority at the start and the lock during the transaction).
    a_wr_m1_not_owner: assert property (wr_busy && wr_owner |-> !(M1.AWREADY || M1.WREADY || M1.BVALID))
        else fail("A-WR-LOCK", "M1 sees AWREADY/WREADY/BVALID while M2 owns the write grant");
    a_wr_m2_not_owner: assert property (wr_busy && !wr_owner |-> !(M2.AWREADY || M2.WREADY || M2.BVALID))
        else fail("A-WR-PRIO", "M2 sees AWREADY/WREADY/BVALID while M1 owns the write grant (M1 has priority)");
    a_rd_m1_not_owner: assert property (rd_busy && rd_owner |-> !(M1.ARREADY || M1.RVALID))
        else fail("A-RD-LOCK", "M1 sees ARREADY/RVALID while M2 owns the read grant");
    a_rd_m2_not_owner: assert property (rd_busy && !rd_owner |-> !(M2.ARREADY || M2.RVALID))
        else fail("A-RD-PRIO", "M2 sees ARREADY/RVALID while M1 owns the read grant (M1 has priority)");

    // Idle: nothing is granted yet.
    a_wr_idle: assert property (!wr_busy |-> !(M1.AWREADY || M2.AWREADY || M1.BVALID || M2.BVALID))
        else fail("A-WR-IDLE", "AWREADY/BVALID without a write grant");
    a_rd_idle: assert property (!rd_busy |-> !(M1.ARREADY || M2.ARREADY || M1.RVALID || M2.RVALID))
        else fail("A-RD-IDLE", "ARREADY/RVALID without a read grant");
endmodule
