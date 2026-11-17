// Smoke test: proves the UVC against the DUT before the scoreboard exists.
//  1. both managers write/read back every window (zero delay)
//  2. the same with random timing and slave delays
//  3. unmapped accesses return DECERR (RDATA = 0 on reads)
//  4. concurrent read (M2) and write (M1)
// Checks here are test-local; the scoreboard replaces them later.

class axi_ic_smoke_test extends axi_ic_base_test;
    `uvm_component_utils(axi_ic_smoke_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void configure(axi_ic_cfg c);
        c.slave_dly_min = 0;
        c.slave_dly_max = 3;
    endfunction

    function void chk_true(bit cond, string msg);
        if (!cond) `uvm_error("SMOKE", msg)
    endfunction

    task sweep(bit no_delay);
        bit [1:0]    resp;
        axi4l_data_t rdata;
        axi4l_addr_t a;
        axi4l_data_t d;
        for (int m = 0; m < axi_ic_cfg::NUM_M; m++) begin
            for (int s = 0; s < axi_ic_cfg::NUM_S; s++) begin
                a = cfg.base[s] + axi4l_addr_t'(8 * (m + 1));
                d = axi4l_rand_data();
                write(m, a, d, resp, no_delay);
                chk_true(resp == AXI4L_RESP_OKAY, $sformatf("M%0d write S%0d resp=%0b", m + 1, s + 1, resp));
                read(m, a, rdata, resp, no_delay);
                chk_true(resp == AXI4L_RESP_OKAY, $sformatf("M%0d read S%0d resp=%0b", m + 1, s + 1, resp));
                chk_true(rdata === d, $sformatf("M%0d S%0d readback 0x%0h != 0x%0h", m + 1, s + 1, rdata, d));
            end
        end
    endtask

    virtual task run_test_body();
        bit [1:0]    resp;
        axi4l_data_t rdata, wd;
        axi4l_addr_t a_wr, a_rd;
        axi4l_data_t unmapped_signature;

        `uvm_info("SMOKE", "sweep: zero delay", UVM_LOW)
        sweep(1);
        `uvm_info("SMOKE", "sweep: random timing", UVM_LOW)
        sweep(0);

        `uvm_info("SMOKE", "unmapped accesses", UVM_LOW)
        for (int m = 0; m < axi_ic_cfg::NUM_M; m++) begin
            write(m, axi4l_addr_t'(32'h0000_9000), 32'hDEAD_BEEF, resp);
            chk_true(resp == AXI4L_RESP_DECERR, $sformatf("M%0d unmapped write resp=%0b", m + 1, resp));
            read(m, axi4l_addr_t'(32'h0000_9000), rdata, resp);
            chk_true(resp == AXI4L_RESP_DECERR, $sformatf("M%0d unmapped read resp=%0b", m + 1, resp));
            chk_true(rdata === '0, $sformatf("M%0d unmapped read data 0x%0h", m + 1, rdata));
        end

        `uvm_info("SMOKE", "concurrent write (M1) and read (M2)", UVM_LOW)
        a_wr = cfg.base[2] + 32'h40;
        a_rd = cfg.base[5] + 32'h80;
        wd   = 32'hA5A5_0001;
        fork
            write(0, a_wr, wd, resp);
            begin
                bit [1:0] rresp;
                read(1, a_rd, rdata, rresp);
                chk_true(rresp == AXI4L_RESP_OKAY, "concurrent read resp");
            end
        join
        read(1, a_wr, rdata, resp);
        chk_true(rdata === wd, $sformatf("concurrent write readback 0x%0h != 0x%0h", rdata, wd));
    endtask
endclass
