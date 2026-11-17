// ==============================================================================
// Copyright (c) Empty Quarter Semiconductor Co. - EQSemi
// All rights reserved.
// EQSEMI CONFIDENTIAL -- do not copy, disclose or distribute without written permission.
// ------------------------------------------------------------------------------
// Project       : edge-ai-eqsemi
// File          : design/axi_interconnect/modules/interconnect/rtl/axi4_lite_1x9_interconnect.sv
// Author(s)     : Ibrahim Al-Sahafi
// Last Modified : 2026-11-01
// ==============================================================================
// AXI4-Lite 1 manager -> 9 subordinates, with one destination per direction.
// Managers must keep at most one write and one read outstanding: do not issue
// another AW before B is accepted, or another AR before R is accepted.
// AWREADY/ARREADY remain ungated, as in the original register architecture.
//
// W uses the captured AW destination, or the live AW decode before AW has been
// accepted. This supports AW-before-W and simultaneous AW/W without a bubble.
// AW and W can be accepted independently; B waits for both handshakes.

module axi4_lite_1x9_interconnect #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,

    // ------------------------------------------------------------------------
    // Address map
    //
    // Default:
    //
    // S1 : 0x0000_0000 - 0x0000_0FFF
    // S2 : 0x0000_1000 - 0x0000_1FFF
    // S3 : 0x0000_2000 - 0x0000_2FFF
    // S4 : 0x0000_3000 - 0x0000_3FFF
    // S5 : 0x0000_4000 - 0x0000_4FFF
    // S6 : 0x0000_5000 - 0x0000_5FFF
    // S7 : 0x0000_6000 - 0x0000_6FFF
    // S8 : 0x0000_7000 - 0x0000_7FFF
    // S9 : 0x0000_8000 - 0x0000_8FFF
    //
    // Change these to your actual address map.
    // ------------------------------------------------------------------------

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
    axi4_lite_if.slave M,
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

    localparam logic [1:0] RESP_OKAY   = 2'b00;
    localparam logic [1:0] RESP_DECERR = 2'b11;

    typedef enum logic [3:0] {
        SEL_S1 = 4'd0,
        SEL_S2 = 4'd1,
        SEL_S3 = 4'd2,
        SEL_S4 = 4'd3,
        SEL_S5 = 4'd4,
        SEL_S6 = 4'd5,
        SEL_S7 = 4'd6,
        SEL_S8 = 4'd7,
        SEL_S9 = 4'd8,
        SEL_ERR = 4'hF
    } slave_sel_t;

    function automatic slave_sel_t decode_address(
        input logic [ADDR_WIDTH-1:0] address
    );
        if ((address & S1_MASK) == (S1_BASE & S1_MASK))
            return SEL_S1;
        else if ((address & S2_MASK) == (S2_BASE & S2_MASK))
            return SEL_S2;
        else if ((address & S3_MASK) == (S3_BASE & S3_MASK))
            return SEL_S3;
        else if ((address & S4_MASK) == (S4_BASE & S4_MASK))
            return SEL_S4;
        else if ((address & S5_MASK) == (S5_BASE & S5_MASK))
            return SEL_S5;
        else if ((address & S6_MASK) == (S6_BASE & S6_MASK))
            return SEL_S6;
        else if ((address & S7_MASK) == (S7_BASE & S7_MASK))
            return SEL_S7;
        else if ((address & S8_MASK) == (S8_BASE & S8_MASK))
            return SEL_S8;
        else if ((address & S9_MASK) == (S9_BASE & S9_MASK))
            return SEL_S9;
        else
            return SEL_ERR;
    endfunction

    slave_sel_t aw_decode, ar_decode, w_route;
    assign aw_decode = decode_address(M.AWADDR);
    assign ar_decode = decode_address(M.ARADDR);

    // The unused destination encoding means no AW has been captured. Retain
    // a captured destination through B, even if AWADDR changes after AW.
    localparam logic [4:0] W_DEST_NONE = 5'b10000;
    logic [4:0] w_dest_q;
    logic       w_done_q;
    logic       aw_hs, w_hs, b_hs;

    assign aw_hs = M.AWVALID && M.AWREADY;
    assign w_hs  = M.WVALID  && M.WREADY;
    assign b_hs  = M.BVALID  && M.BREADY;
    assign w_route = (w_dest_q == W_DEST_NONE)
                   ? aw_decode : slave_sel_t'(w_dest_q[3:0]);

    always_ff @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            w_dest_q <= W_DEST_NONE;
            w_done_q <= 1'b0;
        end else begin
            if (aw_hs)
                w_dest_q <= {1'b0, aw_decode};
            if (w_hs)
                w_done_q <= 1'b1;
            if (b_hs) begin
                w_dest_q <= W_DEST_NONE;
                w_done_q <= 1'b0;
            end
        end
    end

    slave_sel_t r_dest_q;
    logic ar_seen_q;
    logic ar_hs, r_hs;
    assign ar_hs = M.ARVALID && M.ARREADY;
    assign r_hs  = M.RVALID  && M.RREADY;

    always_ff @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            r_dest_q <= SEL_S1;
            ar_seen_q <= 1'b0;
        end else begin
            if (ar_hs) begin
                r_dest_q <= ar_decode;
                ar_seen_q <= 1'b1;
            end
            if (r_hs)
                ar_seen_q <= 1'b0;
        end
    end

    // Address payloads are broadcast; only the decoded destination sees VALID.
    always_comb begin
        S1.AWADDR = M.AWADDR;
        S2.AWADDR = M.AWADDR;
        S3.AWADDR = M.AWADDR;
        S4.AWADDR = M.AWADDR;
        S5.AWADDR = M.AWADDR;
        S6.AWADDR = M.AWADDR;
        S7.AWADDR = M.AWADDR;
        S8.AWADDR = M.AWADDR;
        S9.AWADDR = M.AWADDR;
        S1.AWVALID = 1'b0;
        S2.AWVALID = 1'b0;
        S3.AWVALID = 1'b0;
        S4.AWVALID = 1'b0;
        S5.AWVALID = 1'b0;
        S6.AWVALID = 1'b0;
        S7.AWVALID = 1'b0;
        S8.AWVALID = 1'b0;
        S9.AWVALID = 1'b0;
        M.AWREADY = 1'b0;
        unique case (aw_decode)
            SEL_S1: begin
                S1.AWVALID = M.AWVALID;
                M.AWREADY = S1.AWREADY;
            end
            SEL_S2: begin
                S2.AWVALID = M.AWVALID;
                M.AWREADY = S2.AWREADY;
            end
            SEL_S3: begin
                S3.AWVALID = M.AWVALID;
                M.AWREADY = S3.AWREADY;
            end
            SEL_S4: begin
                S4.AWVALID = M.AWVALID;
                M.AWREADY = S4.AWREADY;
            end
            SEL_S5: begin
                S5.AWVALID = M.AWVALID;
                M.AWREADY = S5.AWREADY;
            end
            SEL_S6: begin
                S6.AWVALID = M.AWVALID;
                M.AWREADY = S6.AWREADY;
            end
            SEL_S7: begin
                S7.AWVALID = M.AWVALID;
                M.AWREADY = S7.AWREADY;
            end
            SEL_S8: begin
                S8.AWVALID = M.AWVALID;
                M.AWREADY = S8.AWREADY;
            end
            SEL_S9: begin
                S9.AWVALID = M.AWVALID;
                M.AWREADY = S9.AWREADY;
            end
            SEL_ERR: M.AWREADY = 1'b1;
            default: ;
        endcase
    end

    always_comb begin
        S1.WDATA = M.WDATA;
        S2.WDATA = M.WDATA;
        S3.WDATA = M.WDATA;
        S4.WDATA = M.WDATA;
        S5.WDATA = M.WDATA;
        S6.WDATA = M.WDATA;
        S7.WDATA = M.WDATA;
        S8.WDATA = M.WDATA;
        S9.WDATA = M.WDATA;
        S1.WVALID = 1'b0;
        S2.WVALID = 1'b0;
        S3.WVALID = 1'b0;
        S4.WVALID = 1'b0;
        S5.WVALID = 1'b0;
        S6.WVALID = 1'b0;
        S7.WVALID = 1'b0;
        S8.WVALID = 1'b0;
        S9.WVALID = 1'b0;
        M.WREADY = 1'b0;

        // Use live AW only until it is captured. VALID does not depend on
        // AWREADY: a subordinate may wait for WVALID before accepting AW.
        // If W completes first, w_done_q prevents a duplicate data transfer.
        if (ARESETn && !w_done_q &&
            ((w_dest_q != W_DEST_NONE) || M.AWVALID)) begin
            unique case (w_route)
                SEL_S1: begin
                    S1.WVALID = M.WVALID;
                    M.WREADY = S1.WREADY;
                end
                SEL_S2: begin
                    S2.WVALID = M.WVALID;
                    M.WREADY = S2.WREADY;
                end
                SEL_S3: begin
                    S3.WVALID = M.WVALID;
                    M.WREADY = S3.WREADY;
                end
                SEL_S4: begin
                    S4.WVALID = M.WVALID;
                    M.WREADY = S4.WREADY;
                end
                SEL_S5: begin
                    S5.WVALID = M.WVALID;
                    M.WREADY = S5.WREADY;
                end
                SEL_S6: begin
                    S6.WVALID = M.WVALID;
                    M.WREADY = S6.WREADY;
                end
                SEL_S7: begin
                    S7.WVALID = M.WVALID;
                    M.WREADY = S7.WREADY;
                end
                SEL_S8: begin
                    S8.WVALID = M.WVALID;
                    M.WREADY = S8.WREADY;
                end
                SEL_S9: begin
                    S9.WVALID = M.WVALID;
                    M.WREADY = S9.WREADY;
                end
                SEL_ERR: M.WREADY = 1'b1;
                default: ;
            endcase
        end
    end

    always_comb begin
        M.BVALID = 1'b0;
        M.BRESP = RESP_OKAY;
        S1.BREADY = 1'b0;
        S2.BREADY = 1'b0;
        S3.BREADY = 1'b0;
        S4.BREADY = 1'b0;
        S5.BREADY = 1'b0;
        S6.BREADY = 1'b0;
        S7.BREADY = 1'b0;
        S8.BREADY = 1'b0;
        S9.BREADY = 1'b0;
        // Both AW and W must be accepted before exposing a response.
        if (w_done_q && (w_dest_q != W_DEST_NONE)) begin
            unique case (slave_sel_t'(w_dest_q[3:0]))
                SEL_S1: begin
                    M.BVALID = S1.BVALID;
                    M.BRESP = S1.BRESP;
                    S1.BREADY = M.BREADY;
                end
                SEL_S2: begin
                    M.BVALID = S2.BVALID;
                    M.BRESP = S2.BRESP;
                    S2.BREADY = M.BREADY;
                end
                SEL_S3: begin
                    M.BVALID = S3.BVALID;
                    M.BRESP = S3.BRESP;
                    S3.BREADY = M.BREADY;
                end
                SEL_S4: begin
                    M.BVALID = S4.BVALID;
                    M.BRESP = S4.BRESP;
                    S4.BREADY = M.BREADY;
                end
                SEL_S5: begin
                    M.BVALID = S5.BVALID;
                    M.BRESP = S5.BRESP;
                    S5.BREADY = M.BREADY;
                end
                SEL_S6: begin
                    M.BVALID = S6.BVALID;
                    M.BRESP = S6.BRESP;
                    S6.BREADY = M.BREADY;
                end
                SEL_S7: begin
                    M.BVALID = S7.BVALID;
                    M.BRESP = S7.BRESP;
                    S7.BREADY = M.BREADY;
                end
                SEL_S8: begin
                    M.BVALID = S8.BVALID;
                    M.BRESP = S8.BRESP;
                    S8.BREADY = M.BREADY;
                end
                SEL_S9: begin
                    M.BVALID = S9.BVALID;
                    M.BRESP = S9.BRESP;
                    S9.BREADY = M.BREADY;
                end
                SEL_ERR: begin
                    M.BVALID = 1'b1;
                    M.BRESP = RESP_DECERR;
                end
                default: M.BRESP = RESP_DECERR;
            endcase
        end
    end

    always_comb begin
        S1.ARADDR = M.ARADDR;
        S2.ARADDR = M.ARADDR;
        S3.ARADDR = M.ARADDR;
        S4.ARADDR = M.ARADDR;
        S5.ARADDR = M.ARADDR;
        S6.ARADDR = M.ARADDR;
        S7.ARADDR = M.ARADDR;
        S8.ARADDR = M.ARADDR;
        S9.ARADDR = M.ARADDR;
        S1.ARVALID = 1'b0;
        S2.ARVALID = 1'b0;
        S3.ARVALID = 1'b0;
        S4.ARVALID = 1'b0;
        S5.ARVALID = 1'b0;
        S6.ARVALID = 1'b0;
        S7.ARVALID = 1'b0;
        S8.ARVALID = 1'b0;
        S9.ARVALID = 1'b0;
        M.ARREADY = 1'b0;
        unique case (ar_decode)
            SEL_S1: begin
                S1.ARVALID = M.ARVALID;
                M.ARREADY = S1.ARREADY;
            end
            SEL_S2: begin
                S2.ARVALID = M.ARVALID;
                M.ARREADY = S2.ARREADY;
            end
            SEL_S3: begin
                S3.ARVALID = M.ARVALID;
                M.ARREADY = S3.ARREADY;
            end
            SEL_S4: begin
                S4.ARVALID = M.ARVALID;
                M.ARREADY = S4.ARREADY;
            end
            SEL_S5: begin
                S5.ARVALID = M.ARVALID;
                M.ARREADY = S5.ARREADY;
            end
            SEL_S6: begin
                S6.ARVALID = M.ARVALID;
                M.ARREADY = S6.ARREADY;
            end
            SEL_S7: begin
                S7.ARVALID = M.ARVALID;
                M.ARREADY = S7.ARREADY;
            end
            SEL_S8: begin
                S8.ARVALID = M.ARVALID;
                M.ARREADY = S8.ARREADY;
            end
            SEL_S9: begin
                S9.ARVALID = M.ARVALID;
                M.ARREADY = S9.ARREADY;
            end
            SEL_ERR: M.ARREADY = 1'b1;
            default: ;
        endcase
    end

    always_comb begin
        M.RDATA = '0;
        M.RRESP = RESP_OKAY;
        M.RVALID = 1'b0;
        S1.RREADY = 1'b0;
        S2.RREADY = 1'b0;
        S3.RREADY = 1'b0;
        S4.RREADY = 1'b0;
        S5.RREADY = 1'b0;
        S6.RREADY = 1'b0;
        S7.RREADY = 1'b0;
        S8.RREADY = 1'b0;
        S9.RREADY = 1'b0;
        if (ar_seen_q) begin
            unique case (r_dest_q)
                SEL_S1: begin
                    M.RDATA = S1.RDATA;
                    M.RRESP = S1.RRESP;
                    M.RVALID = S1.RVALID;
                    S1.RREADY = M.RREADY;
                end
                SEL_S2: begin
                    M.RDATA = S2.RDATA;
                    M.RRESP = S2.RRESP;
                    M.RVALID = S2.RVALID;
                    S2.RREADY = M.RREADY;
                end
                SEL_S3: begin
                    M.RDATA = S3.RDATA;
                    M.RRESP = S3.RRESP;
                    M.RVALID = S3.RVALID;
                    S3.RREADY = M.RREADY;
                end
                SEL_S4: begin
                    M.RDATA = S4.RDATA;
                    M.RRESP = S4.RRESP;
                    M.RVALID = S4.RVALID;
                    S4.RREADY = M.RREADY;
                end
                SEL_S5: begin
                    M.RDATA = S5.RDATA;
                    M.RRESP = S5.RRESP;
                    M.RVALID = S5.RVALID;
                    S5.RREADY = M.RREADY;
                end
                SEL_S6: begin
                    M.RDATA = S6.RDATA;
                    M.RRESP = S6.RRESP;
                    M.RVALID = S6.RVALID;
                    S6.RREADY = M.RREADY;
                end
                SEL_S7: begin
                    M.RDATA = S7.RDATA;
                    M.RRESP = S7.RRESP;
                    M.RVALID = S7.RVALID;
                    S7.RREADY = M.RREADY;
                end
                SEL_S8: begin
                    M.RDATA = S8.RDATA;
                    M.RRESP = S8.RRESP;
                    M.RVALID = S8.RVALID;
                    S8.RREADY = M.RREADY;
                end
                SEL_S9: begin
                    M.RDATA = S9.RDATA;
                    M.RRESP = S9.RRESP;
                    M.RVALID = S9.RVALID;
                    S9.RREADY = M.RREADY;
                end
                SEL_ERR: begin
                    M.RRESP = RESP_DECERR;
                    M.RVALID = 1'b1;
                end
                default: M.RRESP = RESP_DECERR;
            endcase
        end
    end
endmodule
