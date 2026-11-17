// ==============================================================================
// Copyright (c) Empty Quarter Semiconductor Co. - EQSemi
// All rights reserved.
// EQSEMI CONFIDENTIAL -- do not copy, disclose or distribute without written permission.
// ------------------------------------------------------------------------------
// Project       : edge-ai-eqsemi
// File          : design/axi_interconnect/blk_tb/sim_tb/tb/axi_ic_tb_top.sv
// ==============================================================================
// UVM top for axi4_lite_2x9_interconnect.
//   M1/M2     <- axi4l master agents (UVC)
//   S1..S9    -> axi4l slave agents  (UVC)

`timescale 1ns/1ps

module axi_ic_tb_top;
    import uvm_pkg::*;
    import axi4l_pkg::*;
    import axi_ic_pkg::*;

    localparam int NUM_M = 2;
    localparam int NUM_S = 9;

    logic ACLK    = 1'b0;
    wire  ARESETn;

    always #5 ACLK = ~ACLK;

    // Power-on reset, released between clock edges; rst_if adds mid-test resets.
    logic por_n = 1'b0;
    axi_ic_rst_if rst_if (ACLK);
    assign ARESETn = por_n & rst_if.rst_n;

    initial begin
        por_n = 1'b0;
        repeat (5) @(posedge ACLK);
        @(negedge ACLK);
        por_n = 1'b1;
    end

    axi4_lite_if #(AXI4L_ADDR_W, AXI4L_DATA_W) managers    [NUM_M] (ACLK, ARESETn);
    axi4_lite_if #(AXI4L_ADDR_W, AXI4L_DATA_W) peripherals [NUM_S] (ACLK, ARESETn);

    axi4_lite_2x9_interconnect #(
        .ADDR_WIDTH (AXI4L_ADDR_W),
        .DATA_WIDTH (AXI4L_DATA_W)
    ) dut (
        .ACLK, .ARESETn,
        .M1(managers[0]),    .M2(managers[1]),
        .S1(peripherals[0]), .S2(peripherals[1]), .S3(peripherals[2]),
        .S4(peripherals[3]), .S5(peripherals[4]), .S6(peripherals[5]),
        .S7(peripherals[6]), .S8(peripherals[7]), .S9(peripherals[8])
    );

    // Arbitration / grant-lock checker and per-port protocol checkers (SVA)
    axi_ic_sva_checker arb_chk (.M1(managers[0]), .M2(managers[1]));

    for (genvar i = 0; i < NUM_M; i++) begin : g_chk_m
        axi4l_protocol_checker #(AXI4L_ADDR_W, AXI4L_DATA_W, 1'b1, $sformatf("M%0d", i+1))
            chk (.bus(managers[i]));
    end
    for (genvar i = 0; i < NUM_S; i++) begin : g_chk_s
        axi4l_protocol_checker #(AXI4L_ADDR_W, AXI4L_DATA_W, 1'b0, $sformatf("S%0d", i+1))
            chk (.bus(peripherals[i]));
    end

    initial begin
        uvm_config_db #(axi4l_vif_t)::set(null, "*", "m_vif_0", managers[0]);
        uvm_config_db #(axi4l_vif_t)::set(null, "*", "m_vif_1", managers[1]);
        uvm_config_db #(axi4l_vif_t)::set(null, "*", "s_vif_0", peripherals[0]);
        uvm_config_db #(axi4l_vif_t)::set(null, "*", "s_vif_1", peripherals[1]);
        uvm_config_db #(axi4l_vif_t)::set(null, "*", "s_vif_2", peripherals[2]);
        uvm_config_db #(axi4l_vif_t)::set(null, "*", "s_vif_3", peripherals[3]);
        uvm_config_db #(axi4l_vif_t)::set(null, "*", "s_vif_4", peripherals[4]);
        uvm_config_db #(axi4l_vif_t)::set(null, "*", "s_vif_5", peripherals[5]);
        uvm_config_db #(axi4l_vif_t)::set(null, "*", "s_vif_6", peripherals[6]);
        uvm_config_db #(axi4l_vif_t)::set(null, "*", "s_vif_7", peripherals[7]);
        uvm_config_db #(axi4l_vif_t)::set(null, "*", "s_vif_8", peripherals[8]);
        uvm_config_db #(virtual axi_ic_rst_if)::set(null, "*", "rst_vif", rst_if);
        run_test();
    end
endmodule
