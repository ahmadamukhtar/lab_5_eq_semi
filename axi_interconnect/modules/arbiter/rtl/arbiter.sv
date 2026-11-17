// ==============================================================================
// Copyright (c) Empty Quarter Semiconductor Co. - EQSemi
// All rights reserved.
// EQSEMI CONFIDENTIAL -- do not copy, disclose or distribute without written permission.
// ------------------------------------------------------------------------------
// Project       : edge-ai-eqsemi
// File          : design/axi_interconnect/modules/arbiter/rtl/arbiter.sv
// Author(s)     : Ibrahim Al-Sahafi
// Last Modified : 2026-09-30
// ==============================================================================
// Two-master fixed-priority arbiter
//
// grant = 1'b0 : M1 is selected
// grant = 1'b1 : M2 is selected
//
// M1 has priority when both request at the same time.  Once a request is
// accepted while the arbiter is idle, the grant is held until done is asserted.
// ============================================================================

module arbiter (
    input  logic ACLK,
    input  logic ARESETn,
    input  logic M1_VALID,
    input  logic M2_VALID,
    input  logic done,   // Indicates that the granted master has completed its transaction. B/R Handshake

    output logic grant,
    output logic AxVALID // AWVALID or ARVALID
);

    logic request;
    logic busy_q;
    logic busy_d;

    assign request = M1_VALID | M2_VALID;

    // Set busy when an idle arbiter sees a request. Keep it set until done.
    always_comb begin
        busy_d = busy_q;

        if (!busy_q && request)
            busy_d = 1'b1;
        else if (busy_q && done)
            busy_d = 1'b0;
    end

    always_ff @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            busy_q <= 1'b0;
            grant  <= 1'b0;
        end else begin
            busy_q <= busy_d;

            // Fixed priority: M1 wins if both VALID signals are asserted.
            if (!busy_q && request)
                grant <= ~M1_VALID;
        end
    end

    // Forward only the VALID signal belonging to the locked grant.
    always_comb begin
        if (!busy_q)
            AxVALID = 1'b0;
        else if (grant)
            AxVALID = M2_VALID;
        else
            AxVALID = M1_VALID;
    end

endmodule
