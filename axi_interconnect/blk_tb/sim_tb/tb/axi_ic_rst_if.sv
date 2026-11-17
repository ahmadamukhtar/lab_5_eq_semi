// Mid-test reset control. The testbench top ANDs rst_n with the power-on reset.
// Reset is asserted and released on the falling clock edge, away from the sampling edge.

interface axi_ic_rst_if (input logic ACLK);
    logic rst_n = 1'b1;

    task automatic pulse(int unsigned cycles = 3);
        @(negedge ACLK);
        rst_n = 1'b0;
        repeat (cycles) @(negedge ACLK);
        rst_n = 1'b1;
    endtask
endinterface
