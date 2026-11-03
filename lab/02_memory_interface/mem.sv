// Activity 2: use the design modport for the memory connection.
module mem(mem_intf.mem_side mbus);
    timeunit 1ns;
    timeprecision 1ps;

    logic [7:0] memory [0:31];

    always_ff @(posedge mbus.clk) begin
        if (mbus.write && !mbus.read)
            memory[mbus.addr] <= mbus.data_in;
        if (mbus.read && !mbus.write)
            mbus.data_out <= memory[mbus.addr];
    end
endmodule
