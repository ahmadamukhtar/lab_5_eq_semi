// Activity 1: verify the memory using reusable tasks and a checker function.
module mem_test (
    input  logic       clk,
    output logic       read,
    output logic       write,
    output logic [4:0] addr,
    output logic [7:0] data_in,
    input  logic [7:0] data_out
);
    timeunit 1ns;
    timeprecision 1ps;

    logic debug;
    int total_errors;

    initial begin
        read = 1'b0;
        write = 1'b0;
        addr = '0;
        data_in = '0;
        debug = $test$plusargs("DEBUG");
        total_errors = 0;
    end

    // Drive on the inactive edge to avoid racing the memory's posedge logic.
    task automatic write_mem(
        input logic [4:0] waddr,
        input logic [7:0] wdata,
        input logic debug_mode = 1'b1
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

    // Sample after the active edge and the memory's nonblocking update.
    task automatic read_mem(
        input  logic [4:0] raddr,
        output logic [7:0] rdata,
        input  logic       debug_mode = 1'b1
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

    // Return 1 only when actual data matches the expected data.
    function automatic bit checkit(
        input logic [4:0] address,
        input logic [7:0] actual,
        input logic [7:0] expected
    );
        if (actual !== expected) begin
            $error("Mismatch addr=%0d actual=%02h expected=%02h",
                   address, actual, expected);
            return 1'b0;
        end
        return 1'b1;
    endfunction

    function automatic void printstatus(input string test_name, input int errors);
        if (errors == 0)
            $display("%s_PASS checks=32", test_name);
        else
            $display("%s_FAIL errors=%0d", test_name, errors);
    endfunction

    initial begin : run_memory_tests
        logic [7:0] actual;
        int errors;

        $timeformat(-9, 0, " ns", 10);
        $display("LAB 5 ACTIVITY 1: memory tasks and functions");

        // Test 1: clear all locations and prove each reads back as zero.
        $display("\nSTEP 1: clear memory and verify all 32 addresses");
        errors = 0;
        for (int i = 0; i < 32; i++)
            write_mem(5'(i), 8'h00, debug);
        for (int i = 0; i < 32; i++) begin
            read_mem(5'(i), actual, debug);
            if (!checkit(5'(i), actual, 8'h00))
                errors++;
        end
        total_errors += errors;
        printstatus("MEMORY_CLEAR", errors);

        // Test 2: write address as data and prove all 32 values are retained.
        $display("\nSTEP 2: write address as data and verify all locations");
        errors = 0;
        for (int i = 0; i < 32; i++)
            write_mem(5'(i), 8'(i), debug);
        for (int i = 0; i < 32; i++) begin
            read_mem(5'(i), actual, debug);
            if (!checkit(5'(i), actual, 8'(i)))
                errors++;
        end
        total_errors += errors;
        printstatus("MEMORY_ADDRESS", errors);

        if (total_errors != 0)
            $fatal(1, "LAB5_MEMORY_SUBPROGRAMS_FAIL errors=%0d", total_errors);
        $display("\nLAB5_MEMORY_SUBPROGRAMS_PASS total_checks=64");
        $finish;
    end
endmodule
