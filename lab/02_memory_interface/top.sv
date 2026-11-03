module top;
    timeunit 1ns;
    timeprecision 1ps;

    logic clk = 1'b0;
    always #5ns clk = ~clk;

    // The interface owns the clock connection and shared bus signals.
    mem_intf mbus(clk);

    mem_test testbench(mbus);
    mem memory(mbus);

    // Capture interface signals and all hierarchy for the waveform demo.
    initial begin
        $shm_open("waves.shm");
        $shm_probe("AS");
    end
endmodule
