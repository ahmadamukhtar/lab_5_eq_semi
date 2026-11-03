// Activity 1: a synchronous 32-word by 8-bit memory.
module mem (
    input  logic       clk,
    input  logic       read,
    input  logic       write,
    input  logic [4:0] addr,
    input  logic [7:0] data_in,
    output logic [7:0] data_out
);
    timeunit 1ns;
    timeprecision 1ps;

    logic [7:0] memory [0:31];

    // The specification forbids simultaneous reads and writes.
    always_ff @(posedge clk) begin
        if (write && !read)
            memory[addr] <= data_in;
        if (read && !write)
            data_out <= memory[addr];
    end
endmodule
