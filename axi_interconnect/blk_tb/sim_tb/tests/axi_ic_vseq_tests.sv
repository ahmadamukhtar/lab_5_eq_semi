// Tests built on the virtual sequences. Each runs a single vseq on env.vseqr.

class axi_ic_vseq_test extends axi_ic_base_test;
    `uvm_component_utils(axi_ic_vseq_test)

    function new(string name = "axi_ic_vseq_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task run_vseq(uvm_sequence_base s);
        s.start(env.vseqr);
    endtask
endclass

class axi_ic_sweep_test extends axi_ic_vseq_test;
    `uvm_component_utils(axi_ic_sweep_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    virtual task run_test_body();
        axi_ic_sweep_vseq s = axi_ic_sweep_vseq::type_id::create("s");
        run_vseq(s);
    endtask
endclass

class axi_ic_decode_test extends axi_ic_vseq_test;
    `uvm_component_utils(axi_ic_decode_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    virtual task run_test_body();
        axi_ic_decode_vseq s = axi_ic_decode_vseq::type_id::create("s");
        run_vseq(s);
    endtask
endclass

class axi_ic_arb_test extends axi_ic_vseq_test;
    `uvm_component_utils(axi_ic_arb_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    virtual function void configure(axi_ic_cfg c);
        c.slave_dly_min = 1; c.slave_dly_max = 4;    // slow subordinates keep both requests pending
    endfunction
    virtual task run_test_body();
        axi_ic_arb_vseq s = axi_ic_arb_vseq::type_id::create("s");
        run_vseq(s);
    endtask
endclass

class axi_ic_conc_test extends axi_ic_vseq_test;
    `uvm_component_utils(axi_ic_conc_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    virtual task run_test_body();
        axi_ic_conc_vseq s = axi_ic_conc_vseq::type_id::create("s");
        run_vseq(s);
    endtask
endclass

class axi_ic_stress_test extends axi_ic_vseq_test;
    `uvm_component_utils(axi_ic_stress_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    virtual task run_test_body();
        axi_ic_stress_vseq s = axi_ic_stress_vseq::type_id::create("s");
        run_vseq(s);
    endtask
endclass

class axi_ic_reset_test extends axi_ic_vseq_test;
    `uvm_component_utils(axi_ic_reset_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    virtual task run_test_body();
        axi_ic_reset_vseq s = axi_ic_reset_vseq::type_id::create("s");
        run_vseq(s);
    endtask
endclass

// Directed sweeps, decode, arbitration, concurrency, stress, reset, in one run.
class axi_ic_full_test extends axi_ic_vseq_test;
    `uvm_component_utils(axi_ic_full_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    virtual task run_test_body();
        axi_ic_sweep_vseq  sw = axi_ic_sweep_vseq::type_id::create("sw");
        axi_ic_decode_vseq dc = axi_ic_decode_vseq::type_id::create("dc");
        axi_ic_arb_vseq    ar = axi_ic_arb_vseq::type_id::create("ar");
        axi_ic_conc_vseq   cc = axi_ic_conc_vseq::type_id::create("cc");
        axi_ic_stress_vseq st = axi_ic_stress_vseq::type_id::create("st");
        axi_ic_reset_vseq  rs = axi_ic_reset_vseq::type_id::create("rs");
        run_vseq(sw);
        run_vseq(dc);
        run_vseq(ar);
        run_vseq(cc);
        run_vseq(st);
        run_vseq(rs);
    endtask
endclass
