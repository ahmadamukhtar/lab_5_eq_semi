//Ali Sabir
///////////////////////////////////////////////////////////////////////////

module mem ( input logic clk,
             mem_intf mbus
	   );
// SYSTEMVERILOG: timeunit and timeprecision specification
timeunit 1ns;
timeprecision 1ns;

// SYSTEMVERILOG: logic data type
logic [7:0] memory [0:31] ;
  
  always @(posedge clk)
    if (mbus.write && !mbus.read)
// SYSTEMVERILOG: time literals
      #1 memory[mbus.addr] <= mbus.data_in;

// SYSTEMVERILOG: always_ff and iff event control
  always_ff @(posedge clk iff ((mbus.read == '1)&&(mbus.write == '0)) )
       mbus.data_out <= memory[mbus.addr];

endmodule
