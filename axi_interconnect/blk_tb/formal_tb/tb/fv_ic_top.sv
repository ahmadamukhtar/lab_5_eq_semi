// Formal wrapper: the DUT with free-driven ports.
//   * Manager-side inputs (m_*) and subordinate-side inputs (s_*) are top-level
//     inputs, i.e. free for the formal tool, then restricted by the assume modules.
//   * Interface members are connected to/from plain vectors so the property
//     modules only see wires.
//
// FV_ONE_MGR / FV_NO_WRITE / FV_NO_READ select which manager channels are enabled.

`timescale 1ns/1ps

`ifdef FV_ONE_MGR
  `define FV_M2_ON 1'b0
`else
  `define FV_M2_ON 1'b1
`endif

`ifdef FV_NO_WRITE
  `define FV_WR_ON 1'b0
`else
  `define FV_WR_ON 1'b1
`endif

`ifdef FV_NO_READ
  `define FV_RD_ON 1'b0
`else
  `define FV_RD_ON 1'b1
`endif

module fv_ic_top #(
    parameter int AW = 32,
    parameter int DW = 32
)(
    input logic ACLK,
    input logic ARESETn,

    // free manager outputs (inputs of the DUT)
    input logic [1:0]          m_awvalid, m_wvalid, m_bready, m_arvalid, m_rready,
    input logic [1:0][AW-1:0]  m_awaddr,  m_araddr,
    input logic [1:0][DW-1:0]  m_wdata,

    // free subordinate outputs (inputs of the DUT)
    input logic [8:0]          s_awready, s_wready, s_bvalid, s_arready, s_rvalid,
    input logic [8:0][1:0]     s_bresp,   s_rresp,
    input logic [8:0][DW-1:0]  s_rdata
);

    axi4_lite_if #(AW, DW) m_if [2] (ACLK, ARESETn);
    axi4_lite_if #(AW, DW) s_if [9] (ACLK, ARESETn);

    axi4_lite_2x9_interconnect #(.ADDR_WIDTH(AW), .DATA_WIDTH(DW)) dut (
        .ACLK, .ARESETn,
        .M1(m_if[0]), .M2(m_if[1]),
        .S1(s_if[0]), .S2(s_if[1]), .S3(s_if[2]),
        .S4(s_if[3]), .S5(s_if[4]), .S6(s_if[5]),
        .S7(s_if[6]), .S8(s_if[7]), .S9(s_if[8])
    );

    // DUT outputs seen from the manager side
    logic [1:0]         m_awready, m_wready, m_bvalid, m_arready, m_rvalid;
    logic [1:0][1:0]    m_bresp, m_rresp;
    logic [1:0][DW-1:0] m_rdata;

    // DUT outputs seen from the subordinate side
    logic [8:0]         s_awvalid, s_wvalid, s_bready, s_arvalid, s_rready;
    logic [8:0][AW-1:0] s_awaddr, s_araddr;
    logic [8:0][DW-1:0] s_wdata;

    generate
        for (genvar i = 0; i < 2; i++) begin : g_m
            assign m_if[i].AWVALID = m_awvalid[i];
            assign m_if[i].AWADDR  = m_awaddr[i];
            assign m_if[i].WVALID  = m_wvalid[i];
            assign m_if[i].WDATA   = m_wdata[i];
            assign m_if[i].BREADY  = m_bready[i];
            assign m_if[i].ARVALID = m_arvalid[i];
            assign m_if[i].ARADDR  = m_araddr[i];
            assign m_if[i].RREADY  = m_rready[i];

            assign m_awready[i] = m_if[i].AWREADY;
            assign m_wready[i]  = m_if[i].WREADY;
            assign m_bvalid[i]  = m_if[i].BVALID;
            assign m_bresp[i]   = m_if[i].BRESP;
            assign m_arready[i] = m_if[i].ARREADY;
            assign m_rvalid[i]  = m_if[i].RVALID;
            assign m_rdata[i]   = m_if[i].RDATA;
            assign m_rresp[i]   = m_if[i].RRESP;
        end

        for (genvar j = 0; j < 9; j++) begin : g_s
            assign s_if[j].AWREADY = s_awready[j];
            assign s_if[j].WREADY  = s_wready[j];
            assign s_if[j].BVALID  = s_bvalid[j];
            assign s_if[j].BRESP   = s_bresp[j];
            assign s_if[j].ARREADY = s_arready[j];
            assign s_if[j].RVALID  = s_rvalid[j];
            assign s_if[j].RDATA   = s_rdata[j];
            assign s_if[j].RRESP   = s_rresp[j];

            assign s_awvalid[j] = s_if[j].AWVALID;
            assign s_awaddr[j]  = s_if[j].AWADDR;
            assign s_wvalid[j]  = s_if[j].WVALID;
            assign s_wdata[j]   = s_if[j].WDATA;
            assign s_bready[j]  = s_if[j].BREADY;
            assign s_arvalid[j] = s_if[j].ARVALID;
            assign s_araddr[j]  = s_if[j].ARADDR;
            assign s_rready[j]  = s_if[j].RREADY;
        end

        // ---- environment assumptions -------------------------------------------------
        for (genvar i = 0; i < 2; i++) begin : g_mgr_env
            fv_mgr_assume #(
                .AW    (AW),
                .DW    (DW),
                .EN_WR (`FV_WR_ON && (i == 0 || `FV_M2_ON)),
                .EN_RD (`FV_RD_ON && (i == 0 || `FV_M2_ON))
            ) u_env (
                .clk(ACLK), .rstn(ARESETn),
                .awvalid(m_awvalid[i]), .awaddr(m_awaddr[i]),
                .wvalid(m_wvalid[i]),   .wdata(m_wdata[i]),
                .bready(m_bready[i]),
                .arvalid(m_arvalid[i]), .araddr(m_araddr[i]),
                .rready(m_rready[i]),
                .awready(m_awready[i]), .wready(m_wready[i]), .bvalid(m_bvalid[i]),
                .arready(m_arready[i]), .rvalid(m_rvalid[i])
            );
        end

        for (genvar j = 0; j < 9; j++) begin : g_sub_env
            fv_sub_assume #(.AW(AW), .DW(DW)) u_env (
                .clk(ACLK), .rstn(ARESETn),
                .awvalid(s_awvalid[j]), .awaddr(s_awaddr[j]),
                .wvalid(s_wvalid[j]),   .wdata(s_wdata[j]),
                .bready(s_bready[j]),
                .arvalid(s_arvalid[j]), .araddr(s_araddr[j]),
                .rready(s_rready[j]),
                .awready(s_awready[j]), .wready(s_wready[j]),
                .bvalid(s_bvalid[j]),   .bresp(s_bresp[j]),
                .arready(s_arready[j]),
                .rdata(s_rdata[j]),     .rresp(s_rresp[j]),
                .rvalid(s_rvalid[j])
            );
        end
    endgenerate

    // ---- properties ---------------------------------------------------------------------
    fv_ic_props #(.AW(AW), .DW(DW)) u_props (
        .clk(ACLK), .rstn(ARESETn),
        .m_awvalid, .m_awready, .m_wvalid, .m_wready, .m_bvalid, .m_bready,
        .m_arvalid, .m_arready, .m_rvalid, .m_rready,
        .m_awaddr,  .m_araddr,  .m_wdata,  .m_rdata,  .m_bresp,  .m_rresp,
        .s_awvalid, .s_awready, .s_wvalid, .s_wready, .s_bvalid, .s_bready,
        .s_arvalid, .s_arready, .s_rvalid, .s_rready,
        .s_awaddr,  .s_araddr,  .s_wdata,  .s_rdata,  .s_bresp,  .s_rresp
    );

endmodule
