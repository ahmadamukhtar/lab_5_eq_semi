// Base test: builds the env and provides the common run/report flow.
// Derived tests override run_test_body().

class axi_ic_base_test extends uvm_test;
    `uvm_component_utils(axi_ic_base_test)

    axi_ic_env env;
    axi_ic_cfg cfg;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        cfg = axi_ic_cfg::type_id::create("cfg");
        configure(cfg);
        uvm_config_db #(axi_ic_cfg)::set(this, "env", "cfg", cfg);
        env = axi_ic_env::type_id::create("env", this);
    endfunction

    // Override to change the address map / delay profile before the env is built.
    virtual function void configure(axi_ic_cfg c);
    endfunction

    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        wait (env.m_agent[0].cfg.vif.ARESETn === 1'b1);
        repeat (5) @(posedge env.m_agent[0].cfg.vif.ACLK);
        run_test_body();
        repeat (10) @(posedge env.m_agent[0].cfg.vif.ACLK);
        phase.drop_objection(this);
    endtask

    virtual task run_test_body();
    endtask

    virtual function void report_phase(uvm_phase phase);
        uvm_report_server rs = uvm_report_server::get_server();
        if (rs.get_severity_count(UVM_ERROR) + rs.get_severity_count(UVM_FATAL) == 0)
            `uvm_info("RESULT", "TEST PASSED", UVM_NONE)
        else
            `uvm_info("RESULT", "TEST FAILED", UVM_NONE)
    endfunction

    // ---- Helpers for directed tests ---------------------------------------
    task write(int mgr, axi4l_addr_t a, axi4l_data_t d, output bit [1:0] resp, input bit no_delay = 1);
        axi4l_write_seq s = axi4l_write_seq::type_id::create("wr");
        s.addr = a; s.data = d; s.no_delay = no_delay;
        s.start(env.m_agent[mgr].wr_sqr);
        resp = s.result.resp;
    endtask

    task read(int mgr, axi4l_addr_t a, output axi4l_data_t d, output bit [1:0] resp, input bit no_delay = 1);
        axi4l_read_seq s = axi4l_read_seq::type_id::create("rd");
        s.addr = a; s.no_delay = no_delay;
        s.start(env.m_agent[mgr].rd_sqr);
        d    = s.result.data;
        resp = s.result.resp;
    endtask
endclass
