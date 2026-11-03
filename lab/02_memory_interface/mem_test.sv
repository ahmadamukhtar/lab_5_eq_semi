// Activity 2: use the interface's methods through its interface port.
// Xcelium 25.03 does not implement importing interface tasks through modports.
module mem_test(mem_intf mbus);
    timeunit 1ns;
    timeprecision 1ps;

    logic debug;

    initial begin
        mbus.read = 1'b0;
        mbus.write = 1'b0;
        mbus.addr = '0;
        mbus.data_in = '0;
        debug = $test$plusargs("DEBUG");
    end

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
        int total_errors;

        $timeformat(-9, 0, " ns", 10);
        total_errors = 0;
        $display("LAB 5 ACTIVITY 2: memory interface and modports");

        // Test 1: use the interface method to clear and check memory.
        $display("\nSTEP 1: clear memory through interface methods");
        errors = 0;
        for (int i = 0; i < 32; i++)
            mbus.write_mem(5'(i), 8'h00, debug);
        for (int i = 0; i < 32; i++) begin
            mbus.read_mem(5'(i), actual, debug);
            if (!checkit(5'(i), actual, 8'h00))
                errors++;
        end
        total_errors += errors;
        printstatus("MEMORY_CLEAR", errors);

        // Test 2: repeat the address-as-data test through the same interface.
        $display("\nSTEP 2: address-as-data test through interface methods");
        errors = 0;
        for (int i = 0; i < 32; i++)
            mbus.write_mem(5'(i), 8'(i), debug);
        for (int i = 0; i < 32; i++) begin
            mbus.read_mem(5'(i), actual, debug);
            if (!checkit(5'(i), actual, 8'(i)))
                errors++;
        end
        total_errors += errors;
        printstatus("MEMORY_ADDRESS", errors);

        if (total_errors != 0)
            $fatal(1, "LAB5_MEMORY_INTERFACE_FAIL errors=%0d", total_errors);
        $display("\nLAB5_MEMORY_INTERFACE_PASS total_checks=64");
        $finish;
    end
endmodule
