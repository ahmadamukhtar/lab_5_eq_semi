// ==============================================================================
// Copyright (c) Empty Quarter Semiconductor Co. - EQSemi
// All rights reserved.
// EQSEMI CONFIDENTIAL -- do not copy, disclose or distribute without written permission.
// ------------------------------------------------------------------------------
// Project       : edge-ai-eqsemi
// File          : design/axi_interconnect/rtl/axi4_lite_2x9_interconnect.sv
// Author(s)     : Ibrahim Al-Sahafi
// Last Modified : 2026-11-01
// ==============================================================================
// ============================================================================
// AXI4-Lite 2 Manager -> 9 Subordinate Interconnect -- register version
//
// This module extends axi4_lite_1x9_interconnect with two independent
// fixed-priority arbiters:
//
//   * the write grant is acquired from AWVALID and held through the B handshake
//   * the read grant is acquired from ARVALID and held through the R handshake
//
// M1 has priority when both managers request the same direction while idle.
// Read and write grants are independent, so one manager may read while the
// other writes. As with the wrapped register-based core, at most one transaction per
// direction may be outstanding across both managers.
// ============================================================================

module axi4_lite_2x9_interconnect #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,

    parameter logic [ADDR_WIDTH-1:0] S1_BASE = ADDR_WIDTH'(32'h00000000),
    parameter logic [ADDR_WIDTH-1:0] S1_MASK = ~ADDR_WIDTH'(32'h00000FFF),
    parameter logic [ADDR_WIDTH-1:0] S2_BASE = ADDR_WIDTH'(32'h00001000),
    parameter logic [ADDR_WIDTH-1:0] S2_MASK = ~ADDR_WIDTH'(32'h00000FFF),
    parameter logic [ADDR_WIDTH-1:0] S3_BASE = ADDR_WIDTH'(32'h00002000),
    parameter logic [ADDR_WIDTH-1:0] S3_MASK = ~ADDR_WIDTH'(32'h00000FFF),
    parameter logic [ADDR_WIDTH-1:0] S4_BASE = ADDR_WIDTH'(32'h00003000),
    parameter logic [ADDR_WIDTH-1:0] S4_MASK = ~ADDR_WIDTH'(32'h00000FFF),
    parameter logic [ADDR_WIDTH-1:0] S5_BASE = ADDR_WIDTH'(32'h00004000),
    parameter logic [ADDR_WIDTH-1:0] S5_MASK = ~ADDR_WIDTH'(32'h00000FFF),
    parameter logic [ADDR_WIDTH-1:0] S6_BASE = ADDR_WIDTH'(32'h00005000),
    parameter logic [ADDR_WIDTH-1:0] S6_MASK = ~ADDR_WIDTH'(32'h00000FFF),
    parameter logic [ADDR_WIDTH-1:0] S7_BASE = ADDR_WIDTH'(32'h00006000),
    parameter logic [ADDR_WIDTH-1:0] S7_MASK = ~ADDR_WIDTH'(32'h00000FFF),
    parameter logic [ADDR_WIDTH-1:0] S8_BASE = ADDR_WIDTH'(32'h00007000),
    parameter logic [ADDR_WIDTH-1:0] S8_MASK = ~ADDR_WIDTH'(32'h00000FFF),
    parameter logic [ADDR_WIDTH-1:0] S9_BASE = ADDR_WIDTH'(32'h00008000),
    parameter logic [ADDR_WIDTH-1:0] S9_MASK = ~ADDR_WIDTH'(32'h00000FFF)
)(
    input logic ACLK,
    input logic ARESETn,
    axi4_lite_if.slave M1,
    axi4_lite_if.slave M2,
    axi4_lite_if.master S1,
    axi4_lite_if.master S2,
    axi4_lite_if.master S3,
    axi4_lite_if.master S4,
    axi4_lite_if.master S5,
    axi4_lite_if.master S6,
    axi4_lite_if.master S7,
    axi4_lite_if.master S8,
    axi4_lite_if.master S9
);

    axi4_lite_if #(ADDR_WIDTH, DATA_WIDTH) M (ACLK, ARESETn);

    logic write_grant;
    logic read_grant;
    logic write_done;
    logic read_done;

    assign write_done = M.BVALID && M.BREADY;
    assign read_done  = M.RVALID && M.RREADY;

    arbiter u_write_arbiter (
        .ACLK      (ACLK),
        .ARESETn   (ARESETn),
        .M1_VALID  (M1.AWVALID),
        .M2_VALID  (M2.AWVALID),
        .done      (write_done),
        .grant     (write_grant),
        .AxVALID   (M.AWVALID)
    );

    arbiter u_read_arbiter (
        .ACLK      (ACLK),
        .ARESETn   (ARESETn),
        .M1_VALID  (M1.ARVALID),
        .M2_VALID  (M2.ARVALID),
        .done      (read_done),
        .grant     (read_grant),
        .AxVALID   (M.ARVALID)
    );

    // ------------------------------------------------------------------------
    // Manager-to-core multiplexers
    // ------------------------------------------------------------------------
    always_comb begin
        if (write_grant) begin
            M.AWADDR  = M2.AWADDR;
            M.WDATA   = M2.WDATA;
            M.WVALID  = M2.WVALID;
            M.BREADY  = M2.BREADY;
        end else begin
            M.AWADDR  = M1.AWADDR;
            M.WDATA   = M1.WDATA;
            M.WVALID  = M1.WVALID;
            M.BREADY  = M1.BREADY;
        end
    end

    always_comb begin
        if (read_grant) begin
            M.ARADDR  = M2.ARADDR;
            M.RREADY  = M2.RREADY;
        end else begin
            M.ARADDR  = M1.ARADDR;
            M.RREADY  = M1.RREADY;
        end
    end

    // ------------------------------------------------------------------------
    // Core-to-manager response demultiplexers
    //
    // AWREADY/ARREADY are gated with the arbiter's forwarded VALID.  Without
    // this gate an idle manager could observe a handshake before its grant had
    // actually been registered by the arbiter.
    // ------------------------------------------------------------------------
    always_comb begin
        M1.AWREADY = 1'b0;
        M2.AWREADY = 1'b0;
        M1.WREADY  = 1'b0;
        M2.WREADY  = 1'b0;
        M1.BVALID  = 1'b0;
        M2.BVALID  = 1'b0;
        M1.BRESP   = M.BRESP;
        M2.BRESP   = M.BRESP;

        if (write_grant) begin
            M2.AWREADY = M.AWREADY && M.AWVALID;
            M2.WREADY  = M.WREADY;
            M2.BVALID  = M.BVALID;
        end else begin
            M1.AWREADY = M.AWREADY && M.AWVALID;
            M1.WREADY  = M.WREADY;
            M1.BVALID  = M.BVALID;
        end
    end

    always_comb begin
        M1.ARREADY = 1'b0;
        M2.ARREADY = 1'b0;
        M1.RVALID  = 1'b0;
        M2.RVALID  = 1'b0;
        M1.RDATA   = M.RDATA;
        M2.RDATA   = M.RDATA;
        M1.RRESP   = M.RRESP;
        M2.RRESP   = M.RRESP;

        if (read_grant) begin
            M2.ARREADY = M.ARREADY && M.ARVALID;
            M2.RVALID  = M.RVALID;
        end else begin
            M1.ARREADY = M.ARREADY && M.ARVALID;
            M1.RVALID  = M.RVALID;
        end
    end

    // Address decoder and 1x9 channel router.
    axi4_lite_1x9_interconnect #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .S1_BASE    (S1_BASE),
        .S1_MASK    (S1_MASK),
        .S2_BASE    (S2_BASE),
        .S2_MASK    (S2_MASK),
        .S3_BASE    (S3_BASE),
        .S3_MASK    (S3_MASK),
        .S4_BASE    (S4_BASE),
        .S4_MASK    (S4_MASK),
        .S5_BASE    (S5_BASE),
        .S5_MASK    (S5_MASK),
        .S6_BASE    (S6_BASE),
        .S6_MASK    (S6_MASK),
        .S7_BASE    (S7_BASE),
        .S7_MASK    (S7_MASK),
        .S8_BASE    (S8_BASE),
        .S8_MASK    (S8_MASK),
        .S9_BASE    (S9_BASE),
        .S9_MASK    (S9_MASK)
    ) u_1x9_core (
        .ACLK,
        .ARESETn,
        .M(M),
        .S1(S1),
        .S2(S2),
        .S3(S3),
        .S4(S4),
        .S5(S5),
        .S6(S6),
        .S7(S7),
        .S8(S8),
        .S9(S9)
    );

endmodule
