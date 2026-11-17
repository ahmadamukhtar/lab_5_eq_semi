// Interconnect functional coverage, sampled from the manager-side monitors only
// (boundary view). Covers SPECS.md section 7.

class axi_ic_coverage extends uvm_component;
    `uvm_component_utils(axi_ic_coverage)

    uvm_analysis_imp_m_item #(axi4l_item,  axi_ic_coverage) m_item_imp;
    uvm_analysis_imp_m_ev   #(axi4l_event, axi_ic_coverage) m_ev_imp;

    axi_ic_cfg cfg;

    // fields sampled by the covergroups
    protected int          c_mgr, c_dest;
    protected axi4l_kind_e c_kind;
    protected bit [1:0]    c_resp;
    protected int          c_off_class;     // 0 first word, 1 last word, 2 middle, 3 just above map, 4 far above map
    protected int          c_data_class;    // 0 zero, 1 ones, 2 0x5A, 3 0xA5, 4 other
    protected int          c_skew;          // write: 0 AW first, 1 W first, 2 same cycle
    protected int          c_lat;           // request done -> response handshake bucket
    protected int          c_stall;         // response VALID -> READY bucket
    protected bit          c_contended;     // request raised while the other manager held the grant
    protected int          c_prev_mgr;      // manager that held the previous access, -1 none
    protected bit          c_overlap;       // read and write in flight together
    protected int          c_rd_mgr, c_wr_mgr;
    protected bit          c_rst_traffic;   // reset seen after at least one access

    protected axi4l_item last_wr, last_rd;
    protected bit        any_traffic;

    covergroup cg_access;
        option.per_instance = 1;
        cp_mgr  : coverpoint c_mgr  { bins m1 = {0}; bins m2 = {1}; }
        cp_kind : coverpoint c_kind { bins wr = {AXI4L_WRITE}; bins rd = {AXI4L_READ}; }
        cp_dest : coverpoint c_dest { bins s[9] = {[0:8]}; bins unmapped = {-1}; }
        cp_resp : coverpoint c_resp { bins okay = {0}; bins slverr = {2}; bins decerr = {3}; }
        x_mgr_kind_dest : cross cp_mgr, cp_kind, cp_dest;
        x_dest_resp     : cross cp_kind, cp_dest, cp_resp {
            ignore_bins unmapped_ok  = binsof(cp_dest.unmapped) && !binsof(cp_resp.decerr);
            ignore_bins mapped_decerr = !binsof(cp_dest.unmapped) && binsof(cp_resp.decerr);
        }
    endgroup

    covergroup cg_addr_data;
        option.per_instance = 1;
        cp_kind  : coverpoint c_kind { bins wr = {AXI4L_WRITE}; bins rd = {AXI4L_READ}; }
        cp_off   : coverpoint c_off_class { bins first = {0}; bins last = {1}; bins mid = {2};
                                            bins above_map_edge = {3}; bins far_above = {4}; }
        cp_data  : coverpoint c_data_class { bins zero = {0}; bins ones = {1}; bins p5a = {2};
                                             bins pa5 = {3}; bins other = {4}; }
        x_kind_off  : cross cp_kind, cp_off;
        x_kind_data : cross cp_kind, cp_data;
    endgroup

    covergroup cg_timing;
        option.per_instance = 1;
        cp_kind  : coverpoint c_kind { bins wr = {AXI4L_WRITE}; bins rd = {AXI4L_READ}; }
        cp_skew  : coverpoint c_skew { bins aw_first = {0}; bins w_first = {1}; bins same = {2}; }
        cp_lat   : coverpoint c_lat  { bins l1 = {1}; bins l2 = {2}; bins l3_5 = {[3:5]}; bins l6_plus = {[6:$]}; }
        cp_stall : coverpoint c_stall{ bins none = {0}; bins s1_4 = {[1:4]}; bins s5_plus = {[5:$]}; }
        x_skew  : cross cp_kind, cp_skew {
            ignore_bins rd_skew = binsof(cp_kind.rd) && !binsof(cp_skew.same);
        }
        x_lat_stall : cross cp_kind, cp_lat, cp_stall;
    endgroup

    covergroup cg_arb;
        option.per_instance = 1;
        cp_kind  : coverpoint c_kind { bins wr = {AXI4L_WRITE}; bins rd = {AXI4L_READ}; }
        cp_mgr   : coverpoint c_mgr  { bins m1 = {0}; bins m2 = {1}; }
        cp_cont  : coverpoint c_contended { bins free = {0}; bins contended = {1}; }
        cp_prev  : coverpoint c_prev_mgr  { bins none = {-1}; bins m1 = {0}; bins m2 = {1}; }
        x_arb    : cross cp_kind, cp_mgr, cp_cont, cp_prev {
            ignore_bins free_no_prev_ok = binsof(cp_cont.contended) && binsof(cp_prev.none);
        }
    endgroup

    covergroup cg_conc;
        option.per_instance = 1;
        cp_overlap : coverpoint c_overlap { bins no = {0}; bins yes = {1}; }
        cp_wr_mgr  : coverpoint c_wr_mgr  { bins m1 = {0}; bins m2 = {1}; }
        cp_rd_mgr  : coverpoint c_rd_mgr  { bins m1 = {0}; bins m2 = {1}; }
        x_conc : cross cp_overlap, cp_wr_mgr, cp_rd_mgr;
    endgroup

    covergroup cg_reset;
        option.per_instance = 1;
        cp_rst : coverpoint c_rst_traffic { bins after_traffic = {1}; }
    endgroup

    function new(string name, uvm_component parent);
        super.new(name, parent);
        cg_access    = new();
        cg_addr_data = new();
        cg_timing    = new();
        cg_arb       = new();
        cg_conc      = new();
        cg_reset     = new();
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        m_item_imp = new("m_item_imp", this);
        m_ev_imp   = new("m_ev_imp", this);
        if (cfg == null && !uvm_config_db #(axi_ic_cfg)::get(this, "", "cfg", cfg))
            `uvm_fatal("COV", "cfg not set")
        last_wr = null; last_rd = null;
    endfunction

    protected function int classify_off(axi4l_addr_t a, int d);
        int unsigned lo, hi;
        axi4l_addr_t top = cfg.base[cfg.NUM_S-1] + ~cfg.mask[cfg.NUM_S-1] + 1;
        if (d < 0) return (a - top < 64) ? 3 : 4;
        lo = cfg.base[d];
        hi = cfg.base[d] + ~cfg.mask[d];
        if ((a & ~axi4l_addr_t'(3)) == lo) return 0;
        if ((a & ~axi4l_addr_t'(3)) == (hi & ~axi4l_addr_t'(3))) return 1;
        return 2;
    endfunction

    protected function int classify_data(axi4l_data_t v);
        if (v == '0) return 0;
        if (v == '1) return 1;
        if (v == axi4l_data_t'(8'h5A) || v == {(AXI4L_DATA_W/8){8'h5A}}) return 2;
        if (v == axi4l_data_t'(8'hA5) || v == {(AXI4L_DATA_W/8){8'hA5}}) return 3;
        return 4;
    endfunction

    function int bucket(int unsigned v);
        return int'(v);
    endfunction

    virtual function void write_m_item(axi4l_item it);
        axi4l_item prev = (it.kind == AXI4L_WRITE) ? last_wr : last_rd;
        axi4l_item oth  = (it.kind == AXI4L_WRITE) ? last_rd : last_wr;
        int unsigned start_c, stop_c, req_done;

        c_mgr  = it.agent_id;
        c_kind = it.kind;
        c_dest = cfg.decode(it.addr);
        c_resp = it.resp;
        c_off_class  = classify_off(it.addr, c_dest);
        c_data_class = classify_data(it.data);

        if (it.kind == AXI4L_WRITE) begin
            start_c  = (it.aw_cycle < it.w_cycle) ? it.aw_cycle : it.w_cycle;
            req_done = (it.aw_cycle > it.w_cycle) ? it.aw_cycle : it.w_cycle;
            stop_c   = it.b_cycle;
            c_skew   = (it.aw_cycle < it.w_cycle) ? 0 : (it.aw_cycle > it.w_cycle) ? 1 : 2;
        end
        else begin
            start_c  = it.ar_cycle;
            req_done = it.ar_cycle;
            stop_c   = it.r_cycle;
            c_skew   = 2;
        end
        c_lat   = bucket(stop_c - req_done);
        c_stall = bucket(stop_c - it.rsp_cycle);

        c_prev_mgr  = (prev == null) ? -1 : prev.agent_id;
        c_contended = (prev != null && prev.agent_id != it.agent_id &&
                       it.req_cycle <= ((it.kind == AXI4L_WRITE) ? prev.b_cycle : prev.r_cycle));

        c_overlap = 0;
        c_wr_mgr  = (it.kind == AXI4L_WRITE) ? it.agent_id : (oth == null ? 0 : oth.agent_id);
        c_rd_mgr  = (it.kind == AXI4L_READ)  ? it.agent_id : (oth == null ? 0 : oth.agent_id);
        if (oth != null) begin
            int unsigned os = (oth.kind == AXI4L_WRITE) ? ((oth.aw_cycle < oth.w_cycle) ? oth.aw_cycle : oth.w_cycle)
                                                         : oth.ar_cycle;
            int unsigned oe = (oth.kind == AXI4L_WRITE) ? oth.b_cycle : oth.r_cycle;
            c_overlap = (os <= stop_c) && (start_c <= oe);
        end

        cg_access.sample();
        cg_addr_data.sample();
        cg_timing.sample();
        cg_arb.sample();
        cg_conc.sample();

        if (it.kind == AXI4L_WRITE) last_wr = it; else last_rd = it;
        any_traffic = 1;
    endfunction

    virtual function void write_m_ev(axi4l_event e);
        if (e.ev == AXI4L_EV_RST_ASSERT && e.agent_id == 0 && any_traffic) begin
            c_rst_traffic = 1;
            cg_reset.sample();
            last_wr = null; last_rd = null;
        end
    endfunction

    virtual function void report_phase(uvm_phase phase);
        `uvm_info("COV", $sformatf("access=%.1f%% addr_data=%.1f%% timing=%.1f%% arb=%.1f%% conc=%.1f%% reset=%.1f%%",
                  cg_access.get_inst_coverage(), cg_addr_data.get_inst_coverage(),
                  cg_timing.get_inst_coverage(), cg_arb.get_inst_coverage(),
                  cg_conc.get_inst_coverage(),   cg_reset.get_inst_coverage()), UVM_NONE)
    endfunction
endclass
