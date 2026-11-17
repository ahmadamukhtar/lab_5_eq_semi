// ==============================================================================
// Copyright (c) Empty Quarter Semiconductor Co. - EQSemi
// All rights reserved.
// EQSEMI CONFIDENTIAL -- do not copy, disclose or distribute without written permission.
// ------------------------------------------------------------------------------
// Project       : edge-ai-eqsemi
// File          : design/axi_interconnect/sim/tb/tb_axi_lite_2x9.sv
// Author(s)     : Ibrahim Al-Sahafi
// Last Modified : 2026-11-01
// ==============================================================================
`timescale 1ns/1ps

// Self-checking integration tests. MAP_MODE: 0 = default map, 1 = relocated
// 8 KiB S9 window, 2 = S8/S9 overlap (the lower-numbered S8 must win).
module tb_axi_lite_2x9 #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int MAP_MODE = 0
);
    localparam logic [ADDR_WIDTH-1:0] S9_BASE = ADDR_WIDTH'(
        MAP_MODE == 1 ? 'h12000 : MAP_MODE == 2 ? 'h7000 : 'h8000);
    localparam logic [ADDR_WIDTH-1:0] S9_MASK = ADDR_WIDTH'(
        MAP_MODE == 1 ? 'hFFFFE000 : 'hFFFFF000);
    logic ACLK = 1'b0;
    logic ARESETn = 1'b0;
    always #5 ACLK = ~ACLK;

    axi4_lite_if #(ADDR_WIDTH, DATA_WIDTH) M [2] (ACLK, ARESETn);
    axi4_lite_if #(ADDR_WIDTH, DATA_WIDTH) S [9] (ACLK, ARESETn);
    logic [1:0][ADDR_WIDTH-1:0] awaddr, araddr;
    logic [1:0][DATA_WIDTH-1:0] wdata, rdata;
    logic [1:0][1:0] bresp, rresp;
    logic [1:0] awvalid, awready, wvalid, wready, bvalid, bready;
    logic [1:0] arvalid, arready, rvalid, rready;
    logic [8:0] s_awvalid, s_wvalid, s_arvalid, s_bready, s_rready;
    int aw_count [9], w_count [9], b_count [9], ar_count [9], r_count [9];
    int expected_writes [9], expected_reads [9];
    int checks = 0;

    axi4_lite_2x9_interconnect #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH),
        .S9_BASE(S9_BASE), .S9_MASK(S9_MASK)
    ) dut (
        .ACLK, .ARESETn, .M1(M[0]), .M2(M[1]),
.S1(S[0]), .S2(S[1]), .S3(S[2]), .S4(S[3]), .S5(S[4]), .S6(S[5]), .S7(S[6]), .S8(S[7]), .S9(S[8])
    );

    // Constant-index interface bridges let the BFM select either manager at run time.
    for (genvar m = 0; m < 2; m++) begin : g_manager
        assign M[m].AWADDR = awaddr[m];
        assign M[m].AWVALID = awvalid[m];
        assign awready[m] = M[m].AWREADY;
        assign M[m].WDATA = wdata[m];
        assign M[m].WVALID = wvalid[m];
        assign wready[m] = M[m].WREADY;
        assign bvalid[m] = M[m].BVALID;
        assign bresp[m] = M[m].BRESP;
        assign M[m].BREADY = bready[m];
        assign M[m].ARADDR = araddr[m];
        assign M[m].ARVALID = arvalid[m];
        assign arready[m] = M[m].ARREADY;
        assign rvalid[m] = M[m].RVALID;
        assign rdata[m] = M[m].RDATA;
        assign rresp[m] = M[m].RRESP;
        assign M[m].RREADY = rready[m];
    end

    for (genvar n = 0; n < 9; n++) begin : g_target
        // Each target has a distinct reset-memory signature and channel delays.
        // S8 returns write SLVERR; S9 returns read SLVERR, while storing data normally.
        axi_lite_slave_model #(
            .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH),
            .SIGNATURE(32'h1111_0000 * (n + 1)),
            .AW_DELAY(n % 3), .W_DELAY((n + 1) % 3),
            .B_DELAY(n % 2 + 1), .AR_DELAY((n + 2) % 3), .R_DELAY(n % 3 + 1),
            .WRITE_RESP(n == 7 ? 2'b10 : 2'b00),
            .READ_RESP(n == 8 ? 2'b10 : 2'b00)
        ) target (.ACLK, .ARESETn, .axi(S[n]));
        assign s_awvalid[n] = S[n].AWVALID;
        assign s_wvalid[n] = S[n].WVALID;
        assign s_arvalid[n] = S[n].ARVALID;
        assign s_bready[n] = S[n].BREADY;
        assign s_rready[n] = S[n].RREADY;
        always @(posedge ACLK) begin
            if (!ARESETn) begin
                aw_count[n] <= 0; w_count[n] <= 0; b_count[n] <= 0;
                ar_count[n] <= 0; r_count[n] <= 0;
            end else begin
                if (S[n].AWVALID && S[n].AWREADY) aw_count[n] <= aw_count[n] + 1;
                if (S[n].WVALID && S[n].WREADY) w_count[n] <= w_count[n] + 1;
                if (S[n].BVALID && S[n].BREADY) b_count[n] <= b_count[n] + 1;
                if (S[n].ARVALID && S[n].ARREADY) ar_count[n] <= ar_count[n] + 1;
                if (S[n].RVALID && S[n].RREADY) r_count[n] <= r_count[n] + 1;
                if (S[n].AWVALID && S[n].AWREADY && S[n].AWADDR !== awaddr[dut.write_grant])
                    $fatal(1, "AW payload altered for S%0d", n + 1);
                if (S[n].WVALID && S[n].WREADY && S[n].WDATA !== wdata[dut.write_grant])
                    $fatal(1, "W payload altered for S%0d", n + 1);
                if (S[n].ARVALID && S[n].ARREADY && S[n].ARADDR !== araddr[dut.read_grant])
                    $fatal(1, "AR payload altered for S%0d", n + 1);
            end
        end
    end

    always @(posedge ACLK) if (ARESETn) begin
        if (!$onehot0(s_awvalid) || !$onehot0(s_wvalid) || !$onehot0(s_arvalid) ||
            !$onehot0(s_bready) || !$onehot0(s_rready) ||
            !$onehot0(bvalid) || !$onehot0(rvalid) ||
            !$onehot0(awready) || !$onehot0(wready) || !$onehot0(arready))
            $fatal(1, "Channel leaked to multiple managers/targets");
    end

    function automatic logic [ADDR_WIDTH-1:0] base(input int n);
        return n == 8 ? S9_BASE : ADDR_WIDTH'(n * 4096);
    endfunction
    function automatic int physical_target(input int n);
        return MAP_MODE == 2 && n == 8 ? 7 : n;
    endfunction
    function automatic logic [1:0] write_response(input int target);
        return target < 0 ? 2'b11 : target == 7 ? 2'b10 : 2'b00;
    endfunction
    function automatic logic [1:0] read_response(input int target);
        return target < 0 ? 2'b11 : target == 8 ? 2'b10 : 2'b00;
    endfunction

    task automatic write_tx(input int m, input logic [ADDR_WIDTH-1:0] address,
                            input logic [DATA_WIDTH-1:0] data, input int target,
                            input int aw_delay = 0, input int w_delay = 0,
                            input int stall = 2);
        if (target >= 0) expected_writes[target]++;
        fork
            begin
                repeat (aw_delay) @(posedge ACLK);
                @(negedge ACLK);
                awaddr[m] = address; awvalid[m] = 1'b1;
                do @(posedge ACLK); while (!awready[m]);
                @(negedge ACLK);
                awvalid[m] = 1'b0; awaddr[m] = '1;
            end
            begin
                repeat (w_delay) @(posedge ACLK);
                @(negedge ACLK);
                wdata[m] = data; wvalid[m] = 1'b1;
                do @(posedge ACLK); while (!wready[m]);
                @(negedge ACLK);
                wvalid[m] = 1'b0; wdata[m] = '0;
            end
        join
        wait (bvalid[m]);
        repeat (stall + 1) begin
            @(posedge ACLK);
            if (!bvalid[m] || bresp[m] !== write_response(target) ||
                dut.write_grant !== 1'(m) || s_bready !== '0)
                $fatal(1, "M%0d write response/grant changed while stalled at %h", m + 1, address);
        end
        @(negedge ACLK); bready[m] = 1'b1;
        @(posedge ACLK);
        if (!bvalid[m]) $fatal(1, "Missing B handshake");
        @(negedge ACLK); bready[m] = 1'b0;
        checks++;
    endtask

    task automatic read_tx(input int m, input logic [ADDR_WIDTH-1:0] address,
                           input logic [DATA_WIDTH-1:0] expected, input int target,
                           input int stall = 2);
        if (target >= 0) expected_reads[target]++;
        @(negedge ACLK); araddr[m] = address; arvalid[m] = 1'b1;
        do @(posedge ACLK); while (!arready[m]);
        @(negedge ACLK); arvalid[m] = 1'b0; araddr[m] = '1;
        wait (rvalid[m]);
        repeat (stall + 1) begin
            @(posedge ACLK);
            if (!rvalid[m] || rdata[m] !== expected || rresp[m] !== read_response(target) ||
                dut.read_grant !== 1'(m) || s_rready !== '0)
                $fatal(1, "M%0d read %h: got %h/%b expected %h/%b", m + 1, address,
                       rdata[m], rresp[m], expected, read_response(target));
        end
        @(negedge ACLK); rready[m] = 1'b1;
        @(posedge ACLK);
        if (!rvalid[m]) $fatal(1, "Missing R handshake");
        @(negedge ACLK); rready[m] = 1'b0;
        checks++;
    endtask

    task automatic check_counts;
        for (int n = 0; n < 9; n++) begin
            if (aw_count[n] != expected_writes[n] || w_count[n] != expected_writes[n] ||
                b_count[n] != expected_writes[n] || ar_count[n] != expected_reads[n] ||
                r_count[n] != expected_reads[n])
                $fatal(1, "S%0d beat counts AW/W/B/AR/R=%0d/%0d/%0d/%0d/%0d expected W/R=%0d/%0d",
                       n + 1, aw_count[n], w_count[n], b_count[n], ar_count[n], r_count[n],
                       expected_writes[n], expected_reads[n]);
        end
    endtask

    task automatic reset_bus;
        @(negedge ACLK);
        ARESETn = 1'b0;
        awaddr = '0; awvalid = '0; wdata = '0; wvalid = '0; bready = '0;
        araddr = '0; arvalid = '0; rready = '0;
        for (int n = 0; n < 9; n++) begin expected_writes[n] = 0; expected_reads[n] = 0; end
        repeat (3) @(posedge ACLK);
        @(negedge ACLK); ARESETn = 1'b1;
        repeat (2) @(posedge ACLK);
        if (bvalid !== '0 || rvalid !== '0) $fatal(1, "Reset left a stale response");
    endtask

    initial begin
        reset_bus();
        $display("[2x9 TB] both managers access every output; AW/W skew and response stalls");
        for (int n = 0; n < 9; n++) begin
            for (int m = 0; m < 2; m++) begin
                write_tx(m, base(n) + ADDR_WIDTH'(16 + 16*m),
                         DATA_WIDTH'(64'hA5A5_1234_BEEF_0000 + (64'(n)*64'd16 + 64'(m))),
                         physical_target(n), m == 0 ? 3 : 0, m == 1 ? 3 : 0);
                read_tx(1-m, base(n) + ADDR_WIDTH'(16 + 16*m),
                        DATA_WIDTH'(64'hA5A5_1234_BEEF_0000 + (64'(n)*64'd16 + 64'(m))), physical_target(n));
            end
            read_tx(n % 2, base(n), DATA_WIDTH'(64'h1111_0000 * (64'(physical_target(n)) + 64'd1)), physical_target(n));
            read_tx(1-n % 2, base(n) + ADDR_WIDTH'((n == 8 && MAP_MODE == 1 ? 8192 : 4096) - DATA_WIDTH/8),
                    DATA_WIDTH'(64'h1111_0000 * (64'(physical_target(n)) + 64'd1)) | DATA_WIDTH'(255), physical_target(n));
        end

        $display("[2x9 TB] simultaneous writes: M1 priority and locked grant through a stalled B");
        fork
            write_tx(0, base(8) + ADDR_WIDTH'(64), DATA_WIDTH'('hF001), physical_target(8), 0, 3, 5);
            write_tx(1, base(0) + ADDR_WIDTH'(64), DATA_WIDTH'('hF002), 0);
            begin
                wait (&awvalid); @(posedge ACLK); #1;
                if (dut.write_grant !== 1'b0) $fatal(1, "M1 lost simultaneous write priority");
                wait (bvalid[0]);
                if (bvalid[1] || awready[1] || wready[1]) $fatal(1, "M2 bypassed locked write grant");
            end
        join
        read_tx(1, base(8) + ADDR_WIDTH'(64), DATA_WIDTH'('hF001), physical_target(8));
        read_tx(0, base(0) + ADDR_WIDTH'(64), DATA_WIDTH'('hF002), 0);

        $display("[2x9 TB] simultaneous reads: M1 priority and locked grant through a stalled R");
        fork
            read_tx(0, base(8) + ADDR_WIDTH'(64), DATA_WIDTH'('hF001), physical_target(8), 5);
            read_tx(1, base(0) + ADDR_WIDTH'(64), DATA_WIDTH'('hF002), 0);
            begin
                wait (&arvalid); @(posedge ACLK); #1;
                if (dut.read_grant !== 1'b0) $fatal(1, "M1 lost simultaneous read priority");
                wait (rvalid[0]);
                if (rvalid[1] || arready[1]) $fatal(1, "M2 bypassed locked read grant");
            end
        join

        $display("[2x9 TB] independent read/write owners and concurrent unmapped errors");
        fork
            write_tx(1, base(6) + ADDR_WIDTH'(80), DATA_WIDTH'('hCAFE_BABE), 6);
            read_tx(0, base(8) + ADDR_WIDTH'(64), DATA_WIDTH'('hF001), physical_target(8));
        join
        fork
            write_tx(0, ADDR_WIDTH'('h9000), DATA_WIDTH'('hDEAD_BEEF), -1, 0, 3, 4);
            read_tx(1, ADDR_WIDTH'('h9004), '0, -1, 4);
        join
        if (MAP_MODE != 0) begin
            // The former S9 window must stop selecting any target after relocation/overlap.
            write_tx(1, ADDR_WIDTH'('h8000), '0, -1);
            read_tx(0, ADDR_WIDTH'('h8000), '0, -1);
        end
        if (MAP_MODE == 1) begin
            read_tx(0, ADDR_WIDTH'('h11FF8), '0, -1);
            read_tx(1, ADDR_WIDTH'('h14000), '0, -1);
        end
        check_counts();

        $display("[2x9 TB] reset abandons incomplete write and stalled read; next access succeeds");
        @(negedge ACLK); awaddr[0] = base(8); awvalid[0] = 1'b1;
        araddr[1] = base(7); arvalid[1] = 1'b1;
        fork
            begin do @(posedge ACLK); while (!awready[0]); @(negedge ACLK); awvalid[0] = 1'b0; end
            begin do @(posedge ACLK); while (!arready[1]); @(negedge ACLK); arvalid[1] = 1'b0; end
        join
        wait (rvalid[1]);
        reset_bus();
        write_tx(1, base(8) + ADDR_WIDTH'(96), DATA_WIDTH'(64'h9876_5432_1234_ABCD), physical_target(8));
        read_tx(0, base(8) + ADDR_WIDTH'(96), DATA_WIDTH'(64'h9876_5432_1234_ABCD), physical_target(8));
        check_counts();
        $display("[2x9 TB] PASS: %0d accesses; ADDR_WIDTH=%0d DATA_WIDTH=%0d MAP_MODE=%0d",
                 checks, ADDR_WIDTH, DATA_WIDTH, MAP_MODE);
        $finish;
    end
    initial begin
        #200000;
        $fatal(1, "2x9 test timeout");
    end
endmodule
