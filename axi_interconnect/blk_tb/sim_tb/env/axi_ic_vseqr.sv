// Virtual sequencer: handles to the manager sequencers and the config.

class axi_ic_vseqr extends uvm_sequencer;
    `uvm_component_utils(axi_ic_vseqr)

    axi4l_sequencer m_wr_sqr [axi_ic_cfg::NUM_M];
    axi4l_sequencer m_rd_sqr [axi_ic_cfg::NUM_M];
    axi4l_agent_cfg s_cfg    [axi_ic_cfg::NUM_S];
    axi_ic_cfg      cfg;
    virtual axi_ic_rst_if rst_vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
endclass
