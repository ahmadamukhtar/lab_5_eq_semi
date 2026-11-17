// AXI4-Lite UVC: passive monitor (one per port).
//
// Publishes
//   item_ap : one axi4l_item per completed write (at B) / read (at R)
//   ev_ap   : one axi4l_event per channel handshake, plus reset events
//
// Pure transaction extraction: protocol rules are checked by the SVA module
// axi4l_protocol_checker (bound per port in the testbench). Out-of-sequence
// handshakes are ignored here so a protocol violation is reported once, by SVA.
//
// Item timing annotations (monitor clock-cycle counter):
//   aw_cycle/w_cycle/b_cycle/ar_cycle/r_cycle : handshake cycles
//   req_cycle : first cycle AWVALID/ARVALID was high  (arbitration analysis)
//   rsp_cycle : first cycle BVALID/RVALID was high    (response stall analysis)

class axi4l_monitor extends uvm_monitor;
    `uvm_component_utils(axi4l_monitor)

    uvm_analysis_port #(axi4l_item)  item_ap;
    uvm_analysis_port #(axi4l_event) ev_ap;

    axi4l_agent_cfg cfg;
    axi4l_vif_t     vif;

    int unsigned cycle;
    int unsigned wr_count, rd_count;

    protected bit in_reset = 1;

    // write / read transaction in progress
    protected axi4l_item wr_item, rd_item;
    protected bit        aw_seen, w_seen, ar_seen;

    // first-VALID tracking
    protected bit          aw_vs, ar_vs, b_vs, r_vs;
    protected int unsigned aw_vstart, ar_vstart, b_vstart, r_vstart;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        item_ap = new("item_ap", this);
        ev_ap   = new("ev_ap", this);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (cfg == null) `uvm_fatal("NOCFG", "agent cfg not set")
        vif = cfg.vif;
        if (vif == null) `uvm_fatal("NOVIF", "virtual interface not set in agent cfg")
    endfunction

    virtual task run_phase(uvm_phase phase);
        forever begin
            @(posedge vif.ACLK);
            sample();
        end
    endtask

    protected function void clear_state();
        wr_item = null; rd_item = null;
        aw_seen = 0; w_seen = 0; ar_seen = 0;
        aw_vs = 0; ar_vs = 0; b_vs = 0; r_vs = 0;
    endfunction

    protected function void publish_event(axi4l_event_e e, axi4l_addr_t a = '0,
                                          axi4l_data_t d = '0, bit [1:0] r = '0);
        axi4l_event ev = axi4l_event::type_id::create("ev");
        ev.ev        = e;
        ev.cycle     = cycle;
        ev.sim_time  = $time;
        ev.agent_id  = cfg.agent_id;
        ev.port_name = cfg.port_name;
        ev.addr      = a;
        ev.data      = d;
        ev.resp      = r;
        ev_ap.write(ev);
    endfunction

    protected function axi4l_item new_item(axi4l_kind_e k);
        axi4l_item it = axi4l_item::type_id::create("mon_item");
        it.kind      = k;
        it.agent_id  = cfg.agent_id;
        it.port_name = cfg.port_name;
        return it;
    endfunction

    protected function void sample();
        bit aw_hs, w_hs, b_hs, ar_hs, r_hs;

        cycle++;

        if (vif.ARESETn !== 1'b1) begin
            if (!in_reset) begin
                in_reset = 1;
                clear_state();
                publish_event(AXI4L_EV_RST_ASSERT);
            end
            return;
        end
        if (in_reset) begin
            in_reset = 0;
            publish_event(AXI4L_EV_RST_RELEASE);
        end

        aw_hs = (vif.AWVALID === 1'b1) && (vif.AWREADY === 1'b1);
        w_hs  = (vif.WVALID  === 1'b1) && (vif.WREADY  === 1'b1);
        b_hs  = (vif.BVALID  === 1'b1) && (vif.BREADY  === 1'b1);
        ar_hs = (vif.ARVALID === 1'b1) && (vif.ARREADY === 1'b1);
        r_hs  = (vif.RVALID  === 1'b1) && (vif.RREADY  === 1'b1);

        // first cycle each VALID is seen high
        if (vif.AWVALID === 1'b1 && !aw_vs) begin aw_vs = 1; aw_vstart = cycle; end
        if (vif.ARVALID === 1'b1 && !ar_vs) begin ar_vs = 1; ar_vstart = cycle; end
        if (vif.BVALID  === 1'b1 && !b_vs)  begin b_vs  = 1; b_vstart  = cycle; end
        if (vif.RVALID  === 1'b1 && !r_vs)  begin r_vs  = 1; r_vstart  = cycle; end

        // ---- write ----
        if (aw_hs) begin
            publish_event(AXI4L_EV_AW, vif.AWADDR);
            if (!aw_seen) begin
                if (wr_item == null) wr_item = new_item(AXI4L_WRITE);
                wr_item.addr      = vif.AWADDR;
                wr_item.aw_cycle  = cycle;
                wr_item.req_cycle = aw_vstart;
                aw_seen = 1;
            end
            aw_vs = 0;
        end
        if (w_hs) begin
            publish_event(AXI4L_EV_W, '0, vif.WDATA);
            if (!w_seen) begin
                if (wr_item == null) wr_item = new_item(AXI4L_WRITE);
                wr_item.data    = vif.WDATA;
                wr_item.w_cycle = cycle;
                w_seen = 1;
            end
        end
        if (b_hs) begin
            publish_event(AXI4L_EV_B, '0, '0, vif.BRESP);
            if (aw_seen && w_seen) begin
                wr_item.resp      = vif.BRESP;
                wr_item.b_cycle   = cycle;
                wr_item.rsp_cycle = b_vstart;
                wr_count++;
                item_ap.write(wr_item);
            end
            wr_item = null; aw_seen = 0; w_seen = 0; b_vs = 0;
        end

        // ---- read ----
        if (ar_hs) begin
            publish_event(AXI4L_EV_AR, vif.ARADDR);
            if (!ar_seen) begin
                rd_item = new_item(AXI4L_READ);
                rd_item.addr      = vif.ARADDR;
                rd_item.ar_cycle  = cycle;
                rd_item.req_cycle = ar_vstart;
                ar_seen = 1;
            end
            ar_vs = 0;
        end
        if (r_hs) begin
            publish_event(AXI4L_EV_R, '0, vif.RDATA, vif.RRESP);
            if (ar_seen) begin
                rd_item.data      = vif.RDATA;
                rd_item.resp      = vif.RRESP;
                rd_item.r_cycle   = cycle;
                rd_item.rsp_cycle = r_vstart;
                rd_count++;
                item_ap.write(rd_item);
            end
            rd_item = null; ar_seen = 0; r_vs = 0;
        end
    endfunction

    virtual function void report_phase(uvm_phase phase);
        `uvm_info("MON", $sformatf("%s: %0d writes, %0d reads observed", cfg.port_name, wr_count, rd_count), UVM_LOW)
    endfunction
endclass
