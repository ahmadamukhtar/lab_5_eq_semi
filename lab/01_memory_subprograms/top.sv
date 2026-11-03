module top;
    timeunit 1ns;
    timeprecision 1ps;

    logic clk = 1'b0;
    logic read;
    logic write;
    logic [4:0] addr;
    logic [7:0] data_in;
    logic [7:0] data_out;

    // Generate the 10 ns lab clock.
    always #5ns clk = ~clk;

    mem_test testbench (
        .clk, .read, .write, .addr, .data_in, .data_out
    );

    mem memory (
        .clk, .read, .write, .addr, .data_in, .data_out
    );

    // Capture all hierarchy for the in-class SimVision waveform walkthrough.
    initial begin
        $shm_open("waves.shm");
        $shm_probe("AS");
    end
endmodule
