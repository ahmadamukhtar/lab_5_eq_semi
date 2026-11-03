// Activity 2: centralize the bus, clock, access tasks, and directions.
interface mem_intf(input logic clk);
    timeunit 1ns;
    timeprecision 1ps;

    logic [7:0] data_in;
    logic [7:0] data_out;
    logic [4:0] addr;
    logic read;
    logic write;

    // Methods drive away from the rising edge and read after the memory update.
    task automatic write_mem(
        input logic [4:0] waddr,
        input logic [7:0] wdata,
        input logic debug_mode = 1'b0
    );
        @(negedge clk);
        addr = waddr;
        data_in = wdata;
        read = 1'b0;
        write = 1'b1;
        @(negedge clk);
        write = 1'b0;
        if (debug_mode)
            $display("WRITE addr=%0d data=%02h", waddr, wdata);
    endtask

    task automatic read_mem(
        input  logic [4:0] raddr,
        output logic [7:0] rdata,
        input  logic       debug_mode = 1'b0
    );
        @(negedge clk);
        addr = raddr;
        write = 1'b0;
        read = 1'b1;
        @(posedge clk);
        #1ps;
        rdata = data_out;
        @(negedge clk);
        read = 1'b0;
        if (debug_mode)
            $display("READ  addr=%0d data=%02h", raddr, rdata);
    endtask

    // Define the memory-side signal directions.
    modport mem_side (
        input clk, read, write, addr, data_in,
        output data_out
    );

    // Define the intended testbench directions. The installed Xcelium version
    // does not yet support imported interface-task prototypes in a modport.
    modport tb_side (
        input clk, data_out,
        output read, write, addr, data_in
    );
endinterface
