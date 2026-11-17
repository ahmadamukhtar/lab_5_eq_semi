// AXI4-Lite UVC: agent. One class, two roles selected by cfg.mode:
//   AXI4L_MASTER : drives a DUT slave port (requests). Active: write + read
//                  sequencers and a master driver.
//   AXI4L_SLAVE  : drives a DUT master port (responses). Active: slave driver.
// A PASSIVE agent (cfg.is_active = UVM_PASSIVE) only instantiates the monitor.

class axi4l_agent extends uvm_agent;
    `uvm_component_utils(axi4l_agent)

    axi4l_agent_cfg cfg;

    axi4l_monitor       monitor;
    axi4l_sequencer     wr_sqr;
    axi4l_sequencer     rd_sqr;
    axi4l_master_driver m_drv;
    axi4l_slave_driver  s_drv;

    // Forwarded from the monitor
    uvm_analysis_port #(axi4l_item)  item_ap;
    uvm_analysis_port #(axi4l_event) ev_ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (cfg == null && !uvm_config_db #(axi4l_agent_cfg)::get(this, "", "cfg", cfg))
            `uvm_fatal("NOCFG", "axi4l_agent_cfg not set (agent.cfg or config_db key \"cfg\")")
        is_active = cfg.is_active;

        item_ap = new("item_ap", this);
        ev_ap   = new("ev_ap", this);

        monitor     = axi4l_monitor::type_id::create("monitor", this);
        monitor.cfg = cfg;

        if (is_active == UVM_ACTIVE) begin
            if (cfg.mode == AXI4L_MASTER) begin
                wr_sqr    = axi4l_sequencer::type_id::create("wr_sqr", this);
                rd_sqr    = axi4l_sequencer::type_id::create("rd_sqr", this);
                m_drv     = axi4l_master_driver::type_id::create("m_drv", this);
                m_drv.cfg = cfg;
            end
            else begin
                s_drv     = axi4l_slave_driver::type_id::create("s_drv", this);
                s_drv.cfg = cfg;
            end
        end
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        monitor.item_ap.connect(item_ap);
        monitor.ev_ap.connect(ev_ap);
        if (is_active == UVM_ACTIVE && cfg.mode == AXI4L_MASTER) begin
            m_drv.seq_item_port.connect(wr_sqr.seq_item_export);
            m_drv.rd_seq_item_port.connect(rd_sqr.seq_item_export);
        end
    endfunction
endclass
