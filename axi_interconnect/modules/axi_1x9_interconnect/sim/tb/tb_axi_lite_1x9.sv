// ==============================================================================
// Copyright (c) Empty Quarter Semiconductor Co. - EQSemi
// All rights reserved.
// EQSEMI CONFIDENTIAL -- do not copy, disclose or distribute without written permission.
// ------------------------------------------------------------------------------
// Project       : edge-ai-eqsemi
// File          : design/axi_interconnect/modules/interconnect/sim/tb/tb_axi_lite_1x9.sv
// Author(s)     : Ibrahim Al-Sahafi
// Last Modified : 2026-11-01
// ==============================================================================
`timescale 1ns/1ps

// Directed channel timing tests. Subordinate READY/response signals are driven
// independently so the tests can require handshakes in specific clock cycles.
module tb_axi_lite_1x9 #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32
);
    logic ACLK = 1'b0;
    logic ARESETn = 1'b0;
    always #5 ACLK = ~ACLK;

    axi4_lite_if #(ADDR_WIDTH, DATA_WIDTH) M (ACLK, ARESETn);
    axi4_lite_if #(ADDR_WIDTH, DATA_WIDTH) S1 (ACLK, ARESETn);
    axi4_lite_if #(ADDR_WIDTH, DATA_WIDTH) S2 (ACLK, ARESETn);
    axi4_lite_if #(ADDR_WIDTH, DATA_WIDTH) S3 (ACLK, ARESETn);
    axi4_lite_if #(ADDR_WIDTH, DATA_WIDTH) S4 (ACLK, ARESETn);
    axi4_lite_if #(ADDR_WIDTH, DATA_WIDTH) S5 (ACLK, ARESETn);
    axi4_lite_if #(ADDR_WIDTH, DATA_WIDTH) S6 (ACLK, ARESETn);
    axi4_lite_if #(ADDR_WIDTH, DATA_WIDTH) S7 (ACLK, ARESETn);
    axi4_lite_if #(ADDR_WIDTH, DATA_WIDTH) S8 (ACLK, ARESETn);
    axi4_lite_if #(ADDR_WIDTH, DATA_WIDTH) S9 (ACLK, ARESETn);

    axi4_lite_1x9_interconnect #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .ACLK, .ARESETn, .M(M), .S1(S1), .S2(S2), .S3(S3), .S4(S4), .S5(S5), .S6(S6), .S7(S7), .S8(S8), .S9(S9)
    );

    integer aw_count = 0, w_count = 0, b_count = 0;
    always @(posedge ACLK) begin
        if (ARESETn) begin
            if (M.AWVALID && M.AWREADY) aw_count = aw_count + 1;
            if (M.WVALID && M.WREADY) w_count = w_count + 1;
            if (M.BVALID && M.BREADY) b_count = b_count + 1;
        end
    end

    task automatic set_ready(input logic [8:0] aw, input logic [8:0] w);
        {S9.AWREADY, S8.AWREADY, S7.AWREADY, S6.AWREADY, S5.AWREADY, S4.AWREADY, S3.AWREADY, S2.AWREADY, S1.AWREADY} = aw;
        {S9.WREADY, S8.WREADY, S7.WREADY, S6.WREADY, S5.WREADY, S4.WREADY, S3.WREADY, S2.WREADY, S1.WREADY} = w;
    endtask

    task automatic start_write(input logic [ADDR_WIDTH-1:0] addr);
        @(negedge ACLK);
        M.AWADDR = addr;
        M.AWVALID = 1'b1;
        M.WDATA = DATA_WIDTH'(64'h1234_5678_A5A5_00FF);
        M.WVALID = 1'b1;
    endtask

    task automatic check_w(input logic [8:0] dest);
        #1;
        if ({S9.WVALID, S8.WVALID, S7.WVALID, S6.WVALID, S5.WVALID, S4.WVALID, S3.WVALID, S2.WVALID, S1.WVALID} !== dest)
            $fatal(1, "W routed to %b, expected %b",
                   {S9.WVALID, S8.WVALID, S7.WVALID, S6.WVALID, S5.WVALID, S4.WVALID, S3.WVALID, S2.WVALID, S1.WVALID}, dest);
        if (S1.WDATA !== M.WDATA ||
            S2.WDATA !== M.WDATA ||
            S3.WDATA !== M.WDATA ||
            S4.WDATA !== M.WDATA ||
            S5.WDATA !== M.WDATA ||
            S6.WDATA !== M.WDATA ||
            S7.WDATA !== M.WDATA ||
            S8.WDATA !== M.WDATA ||
            S9.WDATA !== M.WDATA)
            $fatal(1, "W data changed during routing");
    endtask

    task automatic finish_write(input logic [8:0] dest, input logic [1:0] resp);
        @(negedge ACLK);
        M.AWVALID = 1'b0;
        M.WVALID = 1'b0;
        M.AWADDR = '1;
        {S9.BVALID, S8.BVALID, S7.BVALID, S6.BVALID, S5.BVALID, S4.BVALID, S3.BVALID, S2.BVALID, S1.BVALID} = dest;
        S1.BRESP = resp;
        S2.BRESP = resp;
        S3.BRESP = resp;
        S4.BRESP = resp;
        S5.BRESP = resp;
        S6.BRESP = resp;
        S7.BRESP = resp;
        S8.BRESP = resp;
        S9.BRESP = resp;
        repeat (3) begin
            @(posedge ACLK);
            if (M.BVALID !== 1'b1 || M.BRESP !== resp)
                $fatal(1, "B response changed under backpressure");
            if ({S9.BREADY, S8.BREADY, S7.BREADY, S6.BREADY, S5.BREADY, S4.BREADY, S3.BREADY, S2.BREADY, S1.BREADY} !== 9'b000000000 || M.WREADY !== 1'b0)
                $fatal(1, "Write advanced while the B response was stalled");
        end
        @(negedge ACLK);
        M.BREADY = 1'b1;
        #1;
        if ({S9.BREADY, S8.BREADY, S7.BREADY, S6.BREADY, S5.BREADY, S4.BREADY, S3.BREADY, S2.BREADY, S1.BREADY} !== dest)
            $fatal(1, "BREADY routed to the wrong subordinate");
        @(posedge ACLK);
        @(negedge ACLK);
        M.BREADY = 1'b0;
        {S9.BVALID, S8.BVALID, S7.BVALID, S6.BVALID, S5.BVALID, S4.BVALID, S3.BVALID, S2.BVALID, S1.BVALID} = 9'b000000000;
        #1;
        if (M.BVALID !== 1'b0 || M.WREADY !== 1'b0)
            $fatal(1, "Stale write destination after the B handshake");
    endtask

    initial begin
        M.AWADDR = '0;
        M.AWVALID = 1'b0;
        M.WDATA = '0;
        M.WVALID = 1'b0;
        M.BREADY = 1'b0;
        M.ARADDR = '0;
        M.ARVALID = 1'b0;
        M.RREADY = 1'b0;
        set_ready(9'b111111111, 9'b111111111);
        {S9.BVALID, S8.BVALID, S7.BVALID, S6.BVALID, S5.BVALID, S4.BVALID, S3.BVALID, S2.BVALID, S1.BVALID} = '0;
        S1.BRESP = '0;
        S2.BRESP = '0;
        S3.BRESP = '0;
        S4.BRESP = '0;
        S5.BRESP = '0;
        S6.BRESP = '0;
        S7.BRESP = '0;
        S8.BRESP = '0;
        S9.BRESP = '0;
        {S9.ARREADY, S8.ARREADY, S7.ARREADY, S6.ARREADY, S5.ARREADY, S4.ARREADY, S3.ARREADY, S2.ARREADY, S1.ARREADY} = '1;
        {S9.RVALID, S8.RVALID, S7.RVALID, S6.RVALID, S5.RVALID, S4.RVALID, S3.RVALID, S2.RVALID, S1.RVALID} = '0;
        S1.RDATA = '0;
        S2.RDATA = '0;
        S3.RDATA = '0;
        S4.RDATA = '0;
        S5.RDATA = '0;
        S6.RDATA = '0;
        S7.RDATA = '0;
        S8.RDATA = '0;
        S9.RDATA = '0;
        S1.RRESP = '0;
        S2.RRESP = '0;
        S3.RRESP = '0;
        S4.RRESP = '0;
        S5.RRESP = '0;
        S6.RRESP = '0;
        S7.RRESP = '0;
        S8.RRESP = '0;
        S9.RRESP = '0;
        repeat (3) @(posedge ACLK);
        @(negedge ACLK);
        ARESETn = 1'b1;

        $display("[1x9 TB] W offered before AW waits for a destination; AW/W handshake together");
        M.WDATA = DATA_WIDTH'(64'h1234_5678_A5A5_00FF);
        M.WVALID = 1'b1;
        repeat (2) begin
            @(posedge ACLK);
            if (M.WREADY !== 1'b0 || {S9.WVALID, S8.WVALID, S7.WVALID, S6.WVALID, S5.WVALID, S4.WVALID, S3.WVALID, S2.WVALID, S1.WVALID} !== 9'b000000000)
                $fatal(1, "W accepted without an AW destination");
        end
        start_write(ADDR_WIDTH'('h0000_0000));
        check_w(9'b000000001);
        if (M.AWREADY !== 1'b1 || M.WREADY !== 1'b1 ||
            S1.AWVALID !== 1'b1 || S1.AWADDR !== M.AWADDR)
            $fatal(1, "Simultaneous AW/W must handshake in the first offered cycle");
        @(posedge ACLK);
        finish_write(9'b000000001, 2'b00);

        $display("[1x9 TB] AW first, delayed W, AWADDR changes immediately after AW");
        set_ready(9'b111111111, 9'b000000000);
        start_write(ADDR_WIDTH'('h0000_1004));
        M.WVALID = 1'b0;
        @(posedge ACLK);
        if (M.AWREADY !== 1'b1 || M.WREADY !== 1'b0)
            $fatal(1, "AW must be accepted independently of W");
        @(negedge ACLK);
        M.AWVALID = 1'b0;
        M.AWADDR = ADDR_WIDTH'('h0000_2000);
        repeat (2) @(posedge ACLK);
        @(negedge ACLK);
        M.WVALID = 1'b1;
        repeat (3) begin
            check_w(9'b000000010);
            @(posedge ACLK);
            if (M.WREADY !== 1'b0 || M.BVALID !== 1'b0)
                $fatal(1, "W/B advanced while WREADY was low");
            @(negedge ACLK);
        end
        set_ready(9'b111111111, 9'b000000010);
        @(posedge ACLK);
        if (M.WREADY !== 1'b1) $fatal(1, "Delayed W never became ready");
        finish_write(9'b000000010, 2'b10);

        $display("[1x9 TB] W accepted first when AWREADY stalls, B still waits for AW");
        set_ready(9'b111111011, 9'b111111111);
        start_write(ADDR_WIDTH'('h0000_2008));
        check_w(9'b000000100);
        if (M.WREADY !== 1'b1 || M.AWREADY !== 1'b0)
            $fatal(1, "WVALID must not depend on AWREADY");
        @(posedge ACLK);
        @(negedge ACLK);
        M.WVALID = 1'b0;
        // Even an early subordinate response must not escape before AW.
        S3.BVALID = 1'b1;
        S3.BRESP = 2'b00;
        repeat (3) begin
            @(posedge ACLK);
            if (M.BVALID !== 1'b0 || M.WREADY !== 1'b0 || S3.BREADY !== 1'b0)
                $fatal(1, "B exposed before AW, or W accepted twice");
        end
        @(negedge ACLK);
        set_ready(9'b111111111, 9'b111111111);
        @(posedge ACLK);
        if (M.AWREADY !== 1'b1) $fatal(1, "Stalled AW never became ready");
        finish_write(9'b000000100, 2'b00);

        $display("[1x9 TB] simultaneous unmapped AW/W returns one stalled DECERR");
        start_write(ADDR_WIDTH'('h0000_9000));
        check_w(9'b000000000);
        if (M.AWREADY !== 1'b1 || M.WREADY !== 1'b1 ||
            {S9.AWVALID, S8.AWVALID, S7.AWVALID, S6.AWVALID, S5.AWVALID, S4.AWVALID, S3.AWVALID, S2.AWVALID, S1.AWVALID} !== 9'b000000000)
            $fatal(1, "Unmapped AW/W should be consumed internally together");
        @(posedge ACLK);
        finish_write(9'b000000000, 2'b11);

        $display("[1x9 TB] unmapped AW first then delayed W");
        start_write(ADDR_WIDTH'('h0000_9004));
        M.WVALID = 1'b0;
        @(posedge ACLK);
        @(negedge ACLK);
        M.AWVALID = 1'b0;
        M.AWADDR = '0;
        repeat (2) begin
            @(posedge ACLK);
            if (M.BVALID !== 1'b0) $fatal(1, "DECERR issued before W");
        end
        @(negedge ACLK);
        M.WVALID = 1'b1;
        check_w(9'b000000000);
        if (M.WREADY !== 1'b1) $fatal(1, "Delayed error W not consumed");
        @(posedge ACLK);
        finish_write(9'b000000000, 2'b11);

        if (aw_count != 5 || w_count != 5 || b_count != 5)
            $fatal(1, "Write counts AW/W/B = %0d/%0d/%0d, expected 5/5/5",
                   aw_count, w_count, b_count);

        $display("[1x9 TB] read destination survives ARADDR changes and R stalls");
        @(negedge ACLK);
        M.ARADDR = ADDR_WIDTH'('h0000_1000);
        M.ARVALID = 1'b1;
        #1;
        if (S2.ARVALID !== 1'b1 || S2.ARADDR !== M.ARADDR)
            $fatal(1, "AR payload routing failed");
        @(posedge ACLK);
        @(negedge ACLK);
        M.ARVALID = 1'b0;
        M.ARADDR = '0;
        S2.RVALID = 1'b1;
        S2.RDATA = DATA_WIDTH'(64'hFEED_1234_CAFE_BABE);
        S2.RRESP = 2'b10;
        repeat (3) begin
            @(posedge ACLK);
            if (M.RVALID !== 1'b1 || M.RDATA !== S2.RDATA || M.RRESP !== 2'b10 ||
                {S9.RREADY, S8.RREADY, S7.RREADY, S6.RREADY, S5.RREADY, S4.RREADY, S3.RREADY, S2.RREADY, S1.RREADY} !== 9'b000000000)
                $fatal(1, "Read response changed under backpressure");
        end
        @(negedge ACLK);
        M.RREADY = 1'b1;
        #1;
        if ({S9.RREADY, S8.RREADY, S7.RREADY, S6.RREADY, S5.RREADY, S4.RREADY, S3.RREADY, S2.RREADY, S1.RREADY} !== 9'b000000010)
            $fatal(1, "RREADY routed to the wrong subordinate");
        @(posedge ACLK);
        @(negedge ACLK);
        M.RREADY = 1'b0;
        S2.RVALID = 1'b0;

        $display("[1x9 TB] reset abandons an S9 AW destination");
        start_write(ADDR_WIDTH'('h0000_8000));
        M.WVALID = 1'b0;
        @(posedge ACLK);
        @(negedge ACLK);
        M.AWVALID = 1'b0;
        ARESETn = 1'b0;
        repeat (2) @(posedge ACLK);
        @(negedge ACLK);
        ARESETn = 1'b1;
        M.WVALID = 1'b1;
        #1;
        if (M.WREADY !== 1'b0 || M.BVALID !== 1'b0 || M.RVALID !== 1'b0)
            $fatal(1, "Reset left a stale transaction");
        M.WVALID = 1'b0;
        start_write(ADDR_WIDTH'('h0000_2000));
        check_w(9'b000000100);
        @(posedge ACLK);
        finish_write(9'b000000100, 2'b00);

        $display("[1x9 TB] every port: one-hot write/read routing and independent response payloads");
        for (int target = 0; target < 9; target++) begin
            start_write(ADDR_WIDTH'(target * 4096 + 16));
            check_w(9'b1 << target);
            #1;
            if ({S9.AWVALID, S8.AWVALID, S7.AWVALID, S6.AWVALID, S5.AWVALID, S4.AWVALID, S3.AWVALID, S2.AWVALID, S1.AWVALID} !== (9'b1 << target))
                $fatal(1, "AW routed incorrectly for S%0d", target + 1);
            @(posedge ACLK);
            finish_write(9'b1 << target, target[0] ? 2'b10 : 2'b00);
            @(negedge ACLK);
            M.ARADDR = ADDR_WIDTH'(target * 4096 + 24);
            M.ARVALID = 1'b1;
            #1;
            if ({S9.ARVALID, S8.ARVALID, S7.ARVALID, S6.ARVALID, S5.ARVALID, S4.ARVALID, S3.ARVALID, S2.ARVALID, S1.ARVALID} !== (9'b1 << target))
                $fatal(1, "AR routed incorrectly for S%0d", target + 1);
            @(posedge ACLK);
            @(negedge ACLK);
            M.ARVALID = 1'b0;
            M.ARADDR = '1;
            {S9.RVALID, S8.RVALID, S7.RVALID, S6.RVALID, S5.RVALID, S4.RVALID, S3.RVALID, S2.RVALID, S1.RVALID} = '1; // Unselected targets deliberately offer stray responses.
            S1.RDATA = DATA_WIDTH'(64'hC0DE_1234_5A5A_0000 + 64'd0);
            S1.RRESP = 2'b00;
            S2.RDATA = DATA_WIDTH'(64'hC0DE_1234_5A5A_0000 + 64'd1);
            S2.RRESP = 2'b10;
            S3.RDATA = DATA_WIDTH'(64'hC0DE_1234_5A5A_0000 + 64'd2);
            S3.RRESP = 2'b00;
            S4.RDATA = DATA_WIDTH'(64'hC0DE_1234_5A5A_0000 + 64'd3);
            S4.RRESP = 2'b10;
            S5.RDATA = DATA_WIDTH'(64'hC0DE_1234_5A5A_0000 + 64'd4);
            S5.RRESP = 2'b00;
            S6.RDATA = DATA_WIDTH'(64'hC0DE_1234_5A5A_0000 + 64'd5);
            S6.RRESP = 2'b10;
            S7.RDATA = DATA_WIDTH'(64'hC0DE_1234_5A5A_0000 + 64'd6);
            S7.RRESP = 2'b00;
            S8.RDATA = DATA_WIDTH'(64'hC0DE_1234_5A5A_0000 + 64'd7);
            S8.RRESP = 2'b10;
            S9.RDATA = DATA_WIDTH'(64'hC0DE_1234_5A5A_0000 + 64'd8);
            S9.RRESP = 2'b00;
            repeat (3) begin
                @(posedge ACLK);
                if (!M.RVALID || M.RDATA !== DATA_WIDTH'(64'hC0DE_1234_5A5A_0000 + 64'(target)) ||
                    M.RRESP !== (target[0] ? 2'b10 : 2'b00) || {S9.RREADY, S8.RREADY, S7.RREADY, S6.RREADY, S5.RREADY, S4.RREADY, S3.RREADY, S2.RREADY, S1.RREADY} !== '0)
                    $fatal(1, "Stalled R payload routed incorrectly for S%0d", target + 1);
            end
            @(negedge ACLK);
            M.RREADY = 1'b1;
            #1;
            if ({S9.RREADY, S8.RREADY, S7.RREADY, S6.RREADY, S5.RREADY, S4.RREADY, S3.RREADY, S2.RREADY, S1.RREADY} !== (9'b1 << target))
                $fatal(1, "RREADY routed incorrectly for S%0d", target + 1);
            @(posedge ACLK);
            @(negedge ACLK);
            M.RREADY = 1'b0;
            {S9.RVALID, S8.RVALID, S7.RVALID, S6.RVALID, S5.RVALID, S4.RVALID, S3.RVALID, S2.RVALID, S1.RVALID} = '0;
        end

        $display("[1x9 TB] an unmapped read returns zero data and stalled DECERR");
        @(negedge ACLK);
        M.ARADDR = ADDR_WIDTH'('h9000);
        M.ARVALID = 1'b1;
        #1;
        if ({S9.ARVALID, S8.ARVALID, S7.ARVALID, S6.ARVALID, S5.ARVALID, S4.ARVALID, S3.ARVALID, S2.ARVALID, S1.ARVALID} !== '0 || !M.ARREADY)
            $fatal(1, "Unmapped AR leaked to a target");
        @(posedge ACLK);
        @(negedge ACLK);
        M.ARVALID = 1'b0;
        M.ARADDR = '0;
        {S9.RVALID, S8.RVALID, S7.RVALID, S6.RVALID, S5.RVALID, S4.RVALID, S3.RVALID, S2.RVALID, S1.RVALID} = '1;
        repeat (3) begin
            @(posedge ACLK);
            if (!M.RVALID || M.RRESP !== 2'b11 || M.RDATA !== '0 || {S9.RREADY, S8.RREADY, S7.RREADY, S6.RREADY, S5.RREADY, S4.RREADY, S3.RREADY, S2.RREADY, S1.RREADY} !== '0)
                $fatal(1, "Unmapped R response changed or leaked READY");
        end
        @(negedge ACLK);
        M.RREADY = 1'b1;
        @(posedge ACLK);
        @(negedge ACLK);
        M.RREADY = 1'b0;
        {S9.RVALID, S8.RVALID, S7.RVALID, S6.RVALID, S5.RVALID, S4.RVALID, S3.RVALID, S2.RVALID, S1.RVALID} = '0;

        $display("[1x9 TB] PASS (ADDR_WIDTH=%0d DATA_WIDTH=%0d)", ADDR_WIDTH, DATA_WIDTH);
        $finish;
    end

    initial begin
        #30000;
        $fatal(1, "1x9 TB timeout");
    end
endmodule
