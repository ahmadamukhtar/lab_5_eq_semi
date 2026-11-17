// ==============================================================================
// Copyright (c) Empty Quarter Semiconductor Co. - EQSemi
// All rights reserved.
// EQSEMI CONFIDENTIAL -- do not copy, disclose or distribute without written permission.
// ------------------------------------------------------------------------------
// Project       : edge-ai-eqsemi
// File          : design/axi_interconnect/sim/tb/axi_lite_slave_model.sv
// Author(s)     : Ibrahim Al-Sahafi
// Last Modified : 2026-11-01
// ==============================================================================
// ============================================================================
// axi_lite_slave_model
//
// AXI4-Lite subordinate with word memory and deterministic channel delays.
// AW and W enter independent queues; B is issued only after both are present.
// Memory starts with a per-target signature to expose incorrect routing.
// WRITE_RESP and READ_RESP select the responses returned to the manager.
// ============================================================================

`timescale 1ns/1ps

// ----------------------------------------------------------------------------
// Small synchronous FIFO used for the subordinate's AW / W queues.
// ----------------------------------------------------------------------------
module tb_sfifo #(
    parameter int WIDTH = 32,
    parameter int DEPTH = 2
)(
    input  logic             clk,
    input  logic             rst_n,
    input  logic             push,
    input  logic [WIDTH-1:0] push_data,
    input  logic             pop,
    output logic [WIDTH-1:0] head_data,
    output logic             full,
    output logic             empty
);
    localparam int PW = (DEPTH <= 1) ? 1 : $clog2(DEPTH);
    localparam int CW = $clog2(DEPTH + 1);

    logic [WIDTH-1:0] mem [0:DEPTH-1];
    logic [PW-1:0]    rd_ptr, wr_ptr;
    logic [CW-1:0]    count;

    assign empty     = (count == 0);
    assign full      = (count == DEPTH[CW-1:0]);
    assign head_data = mem[rd_ptr];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr <= '0;
            wr_ptr <= '0;
            count  <= '0;
        end else begin
            if (push && !full) begin
                mem[wr_ptr] <= push_data;
                wr_ptr      <= (wr_ptr == DEPTH[PW-1:0]-1'b1) ? '0 : wr_ptr + 1'b1;
            end
            if (pop && !empty) begin
                rd_ptr <= (rd_ptr == DEPTH[PW-1:0]-1'b1) ? '0 : rd_ptr + 1'b1;
            end
            case ({(push && !full), (pop && !empty)})
                2'b10:   count <= count + 1'b1;
                2'b01:   count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end
endmodule


module axi_lite_slave_model #(
    parameter int          ADDR_WIDTH = 32,
    parameter int          DATA_WIDTH = 32,
    parameter logic [31:0] SIGNATURE  = 32'h1111_0000,
    parameter int          MEM_WORDS  = 256,
    parameter int          QDEPTH     = 2,

    // Deterministic back-pressure: cycles each channel holds READY low
    // after reset and after every accepted beat.
    parameter int          AW_DELAY   = 1,
    parameter int          W_DELAY    = 1,
    parameter int          B_DELAY    = 1,
    parameter int          AR_DELAY   = 1,
    parameter int          R_DELAY    = 2,
    parameter logic [1:0]  WRITE_RESP = 2'b00,
    parameter logic [1:0]  READ_RESP  = 2'b00
)(
    input  logic                      ACLK,
    input  logic                      ARESETn,

    axi4_lite_if.slave axi
);

    localparam logic [1:0] RESP_OKAY = 2'b00;
    localparam int         IDX_LSB   = $clog2(DATA_WIDTH/8);
    localparam int         IDX_W     = $clog2(MEM_WORDS);

    logic [DATA_WIDTH-1:0] mem [0:MEM_WORDS-1];

    integer i;
    initial begin
        for (i = 0; i < MEM_WORDS; i = i + 1)
            mem[i] = DATA_WIDTH'(SIGNATURE) | DATA_WIDTH'(i);
    end

    function automatic [IDX_W-1:0] word_index(input logic [ADDR_WIDTH-1:0] a);
        word_index = a[IDX_LSB +: IDX_W];
    endfunction

    logic aw_hs, w_hs, b_hs, ar_hs, r_hs;
    assign aw_hs = axi.AWVALID & axi.AWREADY;
    assign w_hs  = axi.WVALID  & axi.WREADY;
    assign b_hs  = axi.BVALID  & axi.BREADY;
    assign ar_hs = axi.ARVALID & axi.ARREADY;
    assign r_hs  = axi.RVALID  & axi.RREADY;

    // ------------------------------------------------------------------
    // Independent AW / W queues
    // ------------------------------------------------------------------
    logic [ADDR_WIDTH-1:0] aw_head;
    logic [DATA_WIDTH-1:0] w_head;
    logic                  awq_full, awq_empty, wq_full, wq_empty;
    logic                  wr_commit;

    tb_sfifo #(.WIDTH(ADDR_WIDTH), .DEPTH(QDEPTH)) u_awq (
        .clk(ACLK), .rst_n(ARESETn),
        .push(aw_hs), .push_data(axi.AWADDR),
        .pop(wr_commit), .head_data(aw_head),
        .full(awq_full), .empty(awq_empty));

    tb_sfifo #(.WIDTH(DATA_WIDTH), .DEPTH(QDEPTH)) u_wq (
        .clk(ACLK), .rst_n(ARESETn),
        .push(w_hs), .push_data(axi.WDATA),
        .pop(wr_commit), .head_data(w_head),
        .full(wq_full), .empty(wq_empty));

    // ------------------------------------------------------------------
    // axi.AWREADY / axi.WREADY : registered, so no combinational VALID -> READY path
    // ------------------------------------------------------------------
    integer aw_dly, w_dly;

    always_ff @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            axi.AWREADY <= 1'b0;
            aw_dly  <= AW_DELAY;
        end else if (aw_hs) begin
            axi.AWREADY <= 1'b0;
            aw_dly  <= AW_DELAY;
        end else if (!axi.AWREADY) begin
            if (aw_dly != 0)      aw_dly  <= aw_dly - 1;
            else if (!awq_full)   axi.AWREADY <= 1'b1;
        end
    end

    always_ff @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            axi.WREADY <= 1'b0;
            w_dly  <= W_DELAY;
        end else if (w_hs) begin
            axi.WREADY <= 1'b0;
            w_dly  <= W_DELAY;
        end else if (!axi.WREADY) begin
            if (w_dly != 0)     w_dly  <= w_dly - 1;
            else if (!wq_full)  axi.WREADY <= 1'b1;
        end
    end

    // ------------------------------------------------------------------
    // Write commit + B channel: B only once BOTH AW and W are present
    // ------------------------------------------------------------------
    integer b_pend, b_dly;

    assign wr_commit = !awq_empty && !wq_empty && (b_pend < 2) && (b_dly == 0);

    always_ff @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            b_pend <= 0;
            b_dly  <= B_DELAY;
            axi.BRESP  <= RESP_OKAY;
        end else begin
            if (wr_commit) begin
                mem[word_index(aw_head)] <= w_head;
                b_dly                    <= B_DELAY;
            end else if (!awq_empty && !wq_empty && (b_dly != 0)) begin
                b_dly <= b_dly - 1;
            end

            b_pend <= b_pend + (wr_commit ? 1 : 0) - (b_hs ? 1 : 0);
            axi.BRESP  <= WRITE_RESP;
        end
    end

    assign axi.BVALID = (b_pend != 0);

    // ------------------------------------------------------------------
    // Read path
    // ------------------------------------------------------------------
    logic [ADDR_WIDTH-1:0] ar_head;
    logic                  arq_full, arq_empty, rd_commit;
    integer                ar_dly, r_dly;

    tb_sfifo #(.WIDTH(ADDR_WIDTH), .DEPTH(QDEPTH)) u_arq (
        .clk(ACLK), .rst_n(ARESETn),
        .push(ar_hs), .push_data(axi.ARADDR),
        .pop(rd_commit), .head_data(ar_head),
        .full(arq_full), .empty(arq_empty));

    always_ff @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            axi.ARREADY <= 1'b0;
            ar_dly  <= AR_DELAY;
        end else if (ar_hs) begin
            axi.ARREADY <= 1'b0;
            ar_dly  <= AR_DELAY;
        end else if (!axi.ARREADY) begin
            if (ar_dly != 0)     ar_dly  <= ar_dly - 1;
            else if (!arq_full)  axi.ARREADY <= 1'b1;
        end
    end

    // One read response in flight at a time.
    assign rd_commit = !arq_empty && !axi.RVALID && (r_dly == 0);

    always_ff @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            axi.RVALID <= 1'b0;
            axi.RDATA  <= '0;
            axi.RRESP  <= RESP_OKAY;
            r_dly  <= R_DELAY;
        end else begin
            if (r_hs) begin
                axi.RVALID <= 1'b0;
                r_dly  <= R_DELAY;
            end else if (rd_commit) begin
                axi.RDATA  <= mem[word_index(ar_head)];
                axi.RRESP  <= READ_RESP;
                axi.RVALID <= 1'b1;
            end else if (!arq_empty && !axi.RVALID && (r_dly != 0)) begin
                r_dly <= r_dly - 1;
            end
        end
    end

endmodule
