// Interconnect env: 2 master agents (M1, M2) and 9 slave agents (S1..S9).
// Scoreboard, coverage model and virtual sequencer.

class axi_ic_env extends uvm_env;
    `uvm_component_utils(axi_ic_env)

    axi_ic_cfg  cfg;

    axi4l_agent m_agent [axi_ic_cfg::NUM_M];
    axi4l_agent s_agent [axi_ic_cfg::NUM_S];
    axi_ic_scoreboard sb;
    axi_ic_coverage   cov;
    axi_ic_vseqr      vseqr;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (cfg == null && !uvm_config_db #(axi_ic_cfg)::get(this, "", "cfg", cfg))
            cfg = axi_ic_cfg::type_id::create("cfg");

        for (int i = 0; i < axi_ic_cfg::NUM_M; i++) begin
            axi4l_agent_cfg ac = axi4l_agent_cfg::type_id::create($sformatf("m_cfg_%0d", i));
            if (!uvm_config_db #(axi4l_vif_t)::get(this, "", $sformatf("m_vif_%0d", i), ac.vif))
                `uvm_fatal("NOVIF", $sformatf("m_vif_%0d not found", i))
            ac.mode      = AXI4L_MASTER;
            ac.agent_id  = i;
            ac.port_name = $sformatf("M%0d", i + 1);
            m_agent[i]     = axi4l_agent::type_id::create($sformatf("m_agent_%0d", i), this);
            m_agent[i].cfg = ac;
        end

        for (int i = 0; i < axi_ic_cfg::NUM_S; i++) begin
            axi4l_agent_cfg ac = axi4l_agent_cfg::type_id::create($sformatf("s_cfg_%0d", i));
            if (!uvm_config_db #(axi4l_vif_t)::get(this, "", $sformatf("s_vif_%0d", i), ac.vif))
                `uvm_fatal("NOVIF", $sformatf("s_vif_%0d not found", i))
            ac.mode      = AXI4L_SLAVE;
            ac.agent_id  = i;
            ac.port_name = $sformatf("S%0d", i + 1);
            ac.signature = cfg.signature(i);
            ac.set_slave_delays(cfg.slave_dly_min, cfg.slave_dly_max);
            ac.slverr_pct = cfg.slverr_pct;
            s_agent[i]     = axi4l_agent::type_id::create($sformatf("s_agent_%0d", i), this);
            s_agent[i].cfg = ac;
        end

        sb = axi_ic_scoreboard::type_id::create("sb", this);
        sb.cfg = cfg;
        cov = axi_ic_coverage::type_id::create("cov", this);
        cov.cfg = cfg;
        vseqr = axi_ic_vseqr::type_id::create("vseqr", this);
        vseqr.cfg = cfg;
        void'(uvm_config_db #(virtual axi_ic_rst_if)::get(this, "", "rst_vif", vseqr.rst_vif));
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        foreach (m_agent[i]) begin
            m_agent[i].item_ap.connect(sb.m_item_imp);
            m_agent[i].ev_ap.connect(sb.m_ev_imp);
            m_agent[i].item_ap.connect(cov.m_item_imp);
            m_agent[i].ev_ap.connect(cov.m_ev_imp);
            vseqr.m_wr_sqr[i] = m_agent[i].wr_sqr;
            vseqr.m_rd_sqr[i] = m_agent[i].rd_sqr;
        end
        foreach (s_agent[i]) begin
            s_agent[i].item_ap.connect(sb.s_item_imp);
            s_agent[i].ev_ap.connect(sb.s_ev_imp);
            vseqr.s_cfg[i] = s_agent[i].cfg;
        end
    endfunction
endclass
