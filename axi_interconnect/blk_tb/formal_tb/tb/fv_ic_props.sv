// Formal properties for axi4_lite_2x9_interconnect (boundary signals only).
//
// Assertions are grouped by define so proofs can be run progressively:
//   FV_ASRT_PROTO  output-side AXI rules (hold/stable, no EXOKAY, B/R ordering, one outstanding)
//   FV_ASRT_ARB    grant ownership, M1 priority, non-owner isolation, one-hot subordinate valids
//   FV_ASRT_ROUTE  request routing and address/data pass-through to the decoded subordinate
//   FV_ASRT_RESP   response routing and pass-through, DECERR on decode miss
//   FV_COVER       reachability covers
//   FV_ASRT_ALL    all of the above
//
// Reference model (kept in this file, derived from the boundary behaviour):
//   idle -> busy at the first edge where any manager raises AWVALID (ARVALID);
//   owner = M1 if M1 requests, else M2; busy clears at the owner's B (R) handshake.
//   dest is latched at the AW (AR) handshake; 4'hF means decode miss.
// One model per direction; read and write grants are independent.

`ifdef FV_ASRT_ALL
  `ifndef FV_ASRT_PROTO
    `define FV_ASRT_PROTO
  `endif
  `ifndef FV_ASRT_ARB
    `define FV_ASRT_ARB
  `endif
  `ifndef FV_ASRT_ROUTE
    `define FV_ASRT_ROUTE
  `endif
  `ifndef FV_ASRT_RESP
    `define FV_ASRT_RESP
  `endif
  `ifndef FV_COVER
    `define FV_COVER
  `endif
`endif

module fv_ic_props
    import fv_ic_pkg::*;
#(
    parameter int AW = 32,
    parameter int DW = 32
)(
    input logic clk,
    input logic rstn,

    // manager side (M1 = index 0, M2 = index 1)
    input logic [1:0]          m_awvalid, m_awready, m_wvalid, m_wready,
                               m_bvalid,  m_bready,  m_arvalid, m_arready,
                               m_rvalid,  m_rready,
    input logic [1:0][AW-1:0]  m_awaddr, m_araddr,
    input logic [1:0][DW-1:0]  m_wdata,  m_rdata,
    input logic [1:0][1:0]     m_bresp,  m_rresp,

    // subordinate side (S1..S9 = index 0..8)
    input logic [8:0]          s_awvalid, s_awready, s_wvalid, s_wready,
                               s_bvalid,  s_bready,  s_arvalid, s_arready,
                               s_rvalid,  s_rready,
    input logic [8:0][AW-1:0]  s_awaddr, s_araddr,
    input logic [8:0][DW-1:0]  s_wdata,  s_rdata,
    input logic [8:0][1:0]     s_bresp,  s_rresp
);

    localparam int NM = 2;
    localparam int NS = 9;
    localparam logic [3:0] MISS = 4'hF;
    localparam logic [1:0] EXOKAY = 2'b01;
    localparam logic [1:0] DECERR = 2'b11;

    default clocking cb @(posedge clk); endclocking
    default disable iff (!rstn);

    // =========================================================================
    // Reference model
    // =========================================================================
    logic       wr_busy, wr_owner, rd_busy, rd_owner;
    logic       aw_seen, w_seen, ar_seen;
    logic [3:0] wr_dest, rd_dest;

    wire aw_hs_o = wr_busy && m_awvalid[wr_owner] && m_awready[wr_owner];
    wire w_hs_o  = wr_busy && m_wvalid[wr_owner]  && m_wready[wr_owner];
    wire b_hs_o  = wr_busy && m_bvalid[wr_owner]  && m_bready[wr_owner];
    wire ar_hs_o = rd_busy && m_arvalid[rd_owner] && m_arready[rd_owner];
    wire r_hs_o  = rd_busy && m_rvalid[rd_owner]  && m_rready[rd_owner];

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            wr_busy <= 1'b0; wr_owner <= 1'b0;
            rd_busy <= 1'b0; rd_owner <= 1'b0;
            aw_seen <= 1'b0; w_seen <= 1'b0; ar_seen <= 1'b0;
            wr_dest <= MISS; rd_dest <= MISS;
        end
        else begin
            if (!wr_busy && (m_awvalid[0] || m_awvalid[1])) begin
                wr_busy  <= 1'b1;
                wr_owner <= !m_awvalid[0];
            end
            else if (b_hs_o) wr_busy <= 1'b0;

            if (!rd_busy && (m_arvalid[0] || m_arvalid[1])) begin
                rd_busy  <= 1'b1;
                rd_owner <= !m_arvalid[0];
            end
            else if (r_hs_o) rd_busy <= 1'b0;

            if (aw_hs_o) begin aw_seen <= 1'b1; wr_dest <= fv_dec(64'(m_awaddr[wr_owner])); end
            if (w_hs_o)  w_seen  <= 1'b1;
            if (b_hs_o)  begin aw_seen <= 1'b0; w_seen <= 1'b0; end

            if (ar_hs_o) begin ar_seen <= 1'b1; rd_dest <= fv_dec(64'(m_araddr[rd_owner])); end
            if (r_hs_o)  ar_seen <= 1'b0;
        end
    end

    // Per-subordinate outstanding tracking (request accepted, response not yet accepted)
    logic [NS-1:0] sw_aw_got, sw_w_got, sw_ar_got;
    generate
        for (genvar j = 0; j < NS; j++) begin : g_sub_flags
            always_ff @(posedge clk or negedge rstn) begin
                if (!rstn) begin
                    sw_aw_got[j] <= 1'b0;
                    sw_w_got[j]  <= 1'b0;
                    sw_ar_got[j] <= 1'b0;
                end
                else begin
                    if (s_awvalid[j] && s_awready[j]) sw_aw_got[j] <= 1'b1;
                    if (s_wvalid[j]  && s_wready[j])  sw_w_got[j]  <= 1'b1;
                    if (s_bvalid[j]  && s_bready[j])  begin sw_aw_got[j] <= 1'b0; sw_w_got[j] <= 1'b0; end
                    if (s_arvalid[j] && s_arready[j]) sw_ar_got[j] <= 1'b1;
                    if (s_rvalid[j]  && s_rready[j])  sw_ar_got[j] <= 1'b0;
                end
            end
        end
    endgenerate

    // =========================================================================
    // PROTO: output-side AXI rules
    // =========================================================================
`ifdef FV_ASRT_PROTO
    generate
        for (genvar i = 0; i < NM; i++) begin : g_proto_m
            a_m_b_hold: assert property (m_bvalid[i] && !m_bready[i] |=> m_bvalid[i] && $stable(m_bresp[i]));
            a_m_r_hold: assert property (m_rvalid[i] && !m_rready[i] |=> m_rvalid[i] && $stable(m_rdata[i]) && $stable(m_rresp[i]));
            a_m_b_legal: assert property (m_bvalid[i] |-> m_bresp[i] != EXOKAY);
            a_m_r_legal: assert property (m_rvalid[i] |-> m_rresp[i] != EXOKAY);
            a_m_b_order: assert property (m_bvalid[i] |-> aw_seen && w_seen);
            a_m_r_order: assert property (m_rvalid[i] |-> ar_seen);
        end
        for (genvar j = 0; j < NS; j++) begin : g_proto_s
            a_s_aw_hold: assert property (s_awvalid[j] && !s_awready[j] |=> s_awvalid[j] && $stable(s_awaddr[j]));
            a_s_w_hold:  assert property (s_wvalid[j]  && !s_wready[j]  |=> s_wvalid[j]  && $stable(s_wdata[j]));
            a_s_ar_hold: assert property (s_arvalid[j] && !s_arready[j] |=> s_arvalid[j] && $stable(s_araddr[j]));
            // the interconnect never has two writes / two reads outstanding on one subordinate
            a_s_one_aw:  assert property (s_awvalid[j] |-> !sw_aw_got[j]);
            a_s_one_w:   assert property (s_wvalid[j]  |-> !sw_w_got[j]);
            a_s_one_ar:  assert property (s_arvalid[j] |-> !sw_ar_got[j]);
        end
    endgenerate
`endif

    // =========================================================================
    // ARB: grant ownership, priority, isolation
    // =========================================================================
`ifdef FV_ASRT_ARB
    a_aw_onehot: assert property ($onehot0(s_awvalid));
    a_w_onehot:  assert property ($onehot0(s_wvalid));
    a_ar_onehot: assert property ($onehot0(s_arvalid));
    a_b_onehot:  assert property ($onehot0(s_bready));
    a_r_onehot:  assert property ($onehot0(s_rready));

    generate
        for (genvar i = 0; i < NM; i++) begin : g_arb
            // the manager that does not hold the grant sees nothing (this includes M1 priority:
            // while M1 owns the grant M2 is isolated, and M2 owns it only if M1 was not requesting)
            a_wr_isolate: assert property (wr_busy && (wr_owner != i) |-> !(m_awready[i] || m_wready[i] || m_bvalid[i]));
            a_rd_isolate: assert property (rd_busy && (rd_owner != i) |-> !(m_arready[i] || m_rvalid[i]));
            // nothing is granted before the arbiter has registered a request
            a_wr_idle: assert property (!wr_busy |-> !(m_awready[i] || m_wready[i] || m_bvalid[i]));
            a_rd_idle: assert property (!rd_busy |-> !(m_arready[i] || m_rvalid[i]));
        end
    endgenerate
`endif

    // =========================================================================
    // ROUTE: requests go to the decoded subordinate only, unchanged
    // =========================================================================
`ifdef FV_ASRT_ROUTE
    generate
        for (genvar j = 0; j < NS; j++) begin : g_route
            a_aw_route: assert property (s_awvalid[j] |->
                wr_busy && !aw_seen && m_awvalid[wr_owner] &&
                fv_dec(64'(m_awaddr[wr_owner])) == 4'(j) && s_awaddr[j] == m_awaddr[wr_owner]);

            // W follows the latched destination, or the live AW decode until AW is accepted
            a_w_route: assert property (s_wvalid[j] |->
                wr_busy && !w_seen && m_wvalid[wr_owner] && s_wdata[j] == m_wdata[wr_owner] &&
                ((aw_seen && wr_dest == 4'(j)) ||
                 (!aw_seen && m_awvalid[wr_owner] && fv_dec(64'(m_awaddr[wr_owner])) == 4'(j))));

            a_ar_route: assert property (s_arvalid[j] |->
                rd_busy && !ar_seen && m_arvalid[rd_owner] &&
                fv_dec(64'(m_araddr[rd_owner])) == 4'(j) && s_araddr[j] == m_araddr[rd_owner]);

            // BREADY / RREADY only to the subordinate that holds the transaction
            a_b_route: assert property (s_bready[j] |->
                wr_busy && aw_seen && w_seen && wr_dest == 4'(j) && m_bready[wr_owner]);
            a_r_route: assert property (s_rready[j] |->
                rd_busy && ar_seen && rd_dest == 4'(j) && m_rready[rd_owner]);
        end
    endgenerate
`endif

    // =========================================================================
    // RESP: responses come from the right subordinate, unchanged; DECERR on miss
    // =========================================================================
`ifdef FV_ASRT_RESP
    generate
        for (genvar j = 0; j < NS; j++) begin : g_resp
            a_b_pass: assert property (wr_busy && m_bvalid[wr_owner] && wr_dest == 4'(j) |->
                s_bvalid[j] && m_bresp[wr_owner] == s_bresp[j]);
            a_r_pass: assert property (rd_busy && m_rvalid[rd_owner] && rd_dest == 4'(j) |->
                s_rvalid[j] && m_rdata[rd_owner] == s_rdata[j] && m_rresp[rd_owner] == s_rresp[j]);
        end
    endgenerate

    a_b_decerr: assert property (wr_busy && m_bvalid[wr_owner] && wr_dest == MISS |->
        m_bresp[wr_owner] == DECERR);
    a_r_decerr: assert property (rd_busy && m_rvalid[rd_owner] && rd_dest == MISS |->
        m_rresp[rd_owner] == DECERR && m_rdata[rd_owner] == '0);
`endif

    // =========================================================================
    // COVER: scenarios are reachable (also checks the assumptions are not over-constraining)
    // =========================================================================
`ifdef FV_COVER
    generate
        for (genvar i = 0; i < NM; i++) begin : g_cov_m
            c_wr_done: cover property (m_bvalid[i] && m_bready[i]);
            c_rd_done: cover property (m_rvalid[i] && m_rready[i]);
            c_wr_blocked: cover property (m_awvalid[i] && !m_awready[i] && wr_busy && (wr_owner != i));
            c_rd_blocked: cover property (m_arvalid[i] && !m_arready[i] && rd_busy && (rd_owner != i));
            c_b_stall: cover property (m_bvalid[i] && !m_bready[i]);
            c_r_stall: cover property (m_rvalid[i] && !m_rready[i]);
        end
        for (genvar j = 0; j < NS; j++) begin : g_cov_s
            c_wr_hs: cover property (s_awvalid[j] && s_awready[j]);
            c_w_hs:  cover property (s_wvalid[j]  && s_wready[j]);
            c_rd_hs: cover property (s_arvalid[j] && s_arready[j]);
            c_slverr_wr: cover property (s_bvalid[j] && s_bready[j] && s_bresp[j] == 2'b10);
            c_slverr_rd: cover property (s_rvalid[j] && s_rready[j] && s_rresp[j] == 2'b10);
        end
    endgenerate

    c_wr_contend:  cover property (!wr_busy && m_awvalid[0] && m_awvalid[1]);
    c_rd_contend:  cover property (!rd_busy && m_arvalid[0] && m_arvalid[1]);
    c_wr_m2_owner: cover property (wr_busy && wr_owner);
    c_rd_m2_owner: cover property (rd_busy && rd_owner);
    c_wr_m2_after_m1: cover property (m_bvalid[0] && m_bready[0] ##[1:$] m_bvalid[1] && m_bready[1]);
    c_conc_rw:      cover property (wr_busy && rd_busy);
    c_conc_rw_diff: cover property (wr_busy && rd_busy && (wr_owner != rd_owner));
    c_w_first_done: cover property (w_seen && !aw_seen);
    c_decerr_wr:    cover property (wr_busy && m_bvalid[wr_owner] && m_bresp[wr_owner] == DECERR);
    c_decerr_rd:    cover property (rd_busy && m_rvalid[rd_owner] && m_rresp[rd_owner] == DECERR);
    c_wr_back2back: cover property (b_hs_o ##1 m_awvalid[0] || m_awvalid[1]);
`endif

endmodule
