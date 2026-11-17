// Interconnect scoreboard: boundary-level, transaction-level checks only.
//
// Inputs : completed items and handshake events from the 2 manager-side monitors
//          and the 9 subordinate-side monitors.
// Checks (IDs refer to SPECS.md):
//   SB-ROUTE  a mapped M-side access appears on exactly the decoded subordinate, nowhere else
//   SB-PASS   address / write data / response / read data equal on both sides
//   SB-DECERR an unmapped access returns DECERR (read data 0) and reaches no subordinate
//   SB-ORDER  response handshake after the request handshakes
//   SB-LOCK   accesses of one direction never overlap (one outstanding write / read)
//   SB-DATA   read data equals the shadow memory (written data, or the default pattern)
//   SB-RST    queues are flushed on reset; the shadow memory survives
//   SB-LEFT   nothing left unmatched at end of test
// Protocol rules are checked by the SVA checkers, not here.

`uvm_analysis_imp_decl(_m_item)
`uvm_analysis_imp_decl(_s_item)
`uvm_analysis_imp_decl(_m_ev)
`uvm_analysis_imp_decl(_s_ev)

class axi_ic_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(axi_ic_scoreboard)

    localparam int NS = axi_ic_cfg::NUM_S;

    uvm_analysis_imp_m_item #(axi4l_item,  axi_ic_scoreboard) m_item_imp;
    uvm_analysis_imp_s_item #(axi4l_item,  axi_ic_scoreboard) s_item_imp;
    uvm_analysis_imp_m_ev   #(axi4l_event, axi_ic_scoreboard) m_ev_imp;
    uvm_analysis_imp_s_ev   #(axi4l_event, axi_ic_scoreboard) s_ev_imp;

    axi_ic_cfg cfg;

    typedef bit [AXI4L_ADDR_W+3:0] key_t;
    typedef struct { int unsigned start; int unsigned stop; axi4l_data_t data; } wr_rec_t;
    typedef struct { int dest; axi4l_addr_t word; axi4l_data_t data;
                     int unsigned ar; int unsigned r; } rd_rec_t;

    protected axi4l_item m_wr_q [$];
    protected axi4l_item m_rd_q [$];
    protected axi4l_item s_wr_q [NS][$];
    protected axi4l_item s_rd_q [NS][$];

    protected wr_rec_t       wr_log [key_t][$];
    protected int unsigned   poison [key_t][$];   // cycles at which a reset left the word unknown
    protected rd_rec_t       rd_chk [$];
    protected bit            pend_aw   [NS];
    protected axi4l_addr_t   pend_addr [NS];

    protected int unsigned max_cycle;
    protected bit          have_wr, have_rd;
    protected int unsigned prev_wr_stop, prev_rd_stop;
    protected int          prev_wr_mgr, prev_rd_mgr;

    // statistics
    int unsigned n_wr, n_rd, n_decerr, n_data_chk, n_data_skip, n_flush;
    int unsigned n_wr_m [2], n_rd_m [2];
    int unsigned n_to_s [NS];

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        m_item_imp = new("m_item_imp", this);
        s_item_imp = new("s_item_imp", this);
        m_ev_imp   = new("m_ev_imp", this);
        s_ev_imp   = new("s_ev_imp", this);
        if (cfg == null && !uvm_config_db #(axi_ic_cfg)::get(this, "", "cfg", cfg))
            `uvm_fatal("SB", "cfg not set")
    endfunction

    function key_t mkkey(int dest, axi4l_addr_t word);
        return {word, 4'(dest)};
    endfunction

    protected function void bump(int unsigned c);
        if (c > max_cycle) max_cycle = c;
    endfunction

    // ------------------------------------------------------------------ inputs
    virtual function void write_m_item(axi4l_item it);
        bump(it.kind == AXI4L_WRITE ? it.b_cycle : it.r_cycle);
        if (it.kind == AXI4L_WRITE) m_wr_q.push_back(it);
        else                        m_rd_q.push_back(it);
        process();
    endfunction

    virtual function void write_s_item(axi4l_item it);
        int d = it.agent_id;
        bump(it.kind == AXI4L_WRITE ? it.b_cycle : it.r_cycle);
        if (it.kind == AXI4L_WRITE) begin
            s_wr_q[d].push_back(it);
            pend_aw[d] = 0;
        end
        else s_rd_q[d].push_back(it);
        process();
    endfunction

    virtual function void write_m_ev(axi4l_event e);
        bump(e.cycle);
        if (e.ev == AXI4L_EV_RST_ASSERT && e.agent_id == 0) flush();
        process();
    endfunction

    virtual function void write_s_ev(axi4l_event e);
        int d = e.agent_id;
        bump(e.cycle);
        case (e.ev)
            AXI4L_EV_AW: begin pend_aw[d] = 1; pend_addr[d] = e.addr; end
            // a write accepted by the slave but never completed may have updated its memory
            AXI4L_EV_RST_ASSERT: begin
                if (pend_aw[d]) poison[mkkey(d, cfg.word_addr(pend_addr[d]))].push_back(e.cycle);
                pend_aw[d] = 0;
            end
            default: ;
        endcase
    endfunction

    protected function void flush();
        n_flush++;
        // writes the subordinate completed but whose response never reached the manager
        // may have changed its memory: the word is unknown until it is written again
        for (int i = 0; i < NS; i++)
            foreach (s_wr_q[i][j])
                poison[mkkey(i, cfg.word_addr(s_wr_q[i][j].addr))].push_back(max_cycle);
        m_wr_q.delete(); m_rd_q.delete();
        for (int i = 0; i < NS; i++) begin s_wr_q[i].delete(); s_rd_q[i].delete(); end
        have_wr = 0; have_rd = 0;
    endfunction

    // -------------------------------------------------------------- matching
    protected function void process();
        while (m_wr_q.size() > 0) begin
            axi4l_item m = m_wr_q[0];
            int d = cfg.decode(m.addr);
            if (d < 0) begin
                m_wr_q.pop_front();
                check_wr_decerr(m);
            end
            else if (s_wr_q[d].size() > 0) begin
                axi4l_item s = s_wr_q[d].pop_front();
                m_wr_q.pop_front();
                check_wr_pair(m, s, d);
            end
            else break;
        end
        while (m_rd_q.size() > 0) begin
            axi4l_item m = m_rd_q[0];
            int d = cfg.decode(m.addr);
            if (d < 0) begin
                m_rd_q.pop_front();
                check_rd_decerr(m);
            end
            else if (s_rd_q[d].size() > 0) begin
                axi4l_item s = s_rd_q[d].pop_front();
                m_rd_q.pop_front();
                check_rd_pair(m, s, d);
            end
            else break;
        end
        sweep();
        settle_reads(0);
    endfunction

    // Anything still unmatched after the pairing window is a routing error.
    protected function void sweep();
        int unsigned lim = cfg.max_wait_cycles;
        while (m_wr_q.size() > 0 && max_cycle > m_wr_q[0].b_cycle + lim) begin
            `uvm_error("SB-ROUTE", $sformatf("M-side write never seen on S%0d: %s",
                       cfg.decode(m_wr_q[0].addr) + 1, m_wr_q[0].convert2string()))
            void'(m_wr_q.pop_front());
        end
        while (m_rd_q.size() > 0 && max_cycle > m_rd_q[0].r_cycle + lim) begin
            `uvm_error("SB-ROUTE", $sformatf("M-side read never seen on S%0d: %s",
                       cfg.decode(m_rd_q[0].addr) + 1, m_rd_q[0].convert2string()))
            void'(m_rd_q.pop_front());
        end
        for (int i = 0; i < NS; i++) begin
            while (s_wr_q[i].size() > 0 && max_cycle > s_wr_q[i][0].b_cycle + lim) begin
                `uvm_error("SB-ROUTE", $sformatf("unexpected write on S%0d, no matching M-side access: %s",
                           i + 1, s_wr_q[i][0].convert2string()))
                void'(s_wr_q[i].pop_front());
            end
            while (s_rd_q[i].size() > 0 && max_cycle > s_rd_q[i][0].r_cycle + lim) begin
                `uvm_error("SB-ROUTE", $sformatf("unexpected read on S%0d, no matching M-side access: %s",
                           i + 1, s_rd_q[i][0].convert2string()))
                void'(s_rd_q[i].pop_front());
            end
        end
    endfunction

    // ------------------------------------------------------------ write checks
    protected function void check_order_wr(axi4l_item m);
        int unsigned first = (m.aw_cycle < m.w_cycle) ? m.aw_cycle : m.w_cycle;
        int unsigned last  = (m.aw_cycle > m.w_cycle) ? m.aw_cycle : m.w_cycle;
        if (m.b_cycle <= last)
            `uvm_error("SB-ORDER", $sformatf("B before/with AW,W: %s", m.convert2string()))
        // the other direction's lock: the next write can only start after the previous B
        if (have_wr && first <= prev_wr_stop)
            `uvm_error("SB-LOCK", $sformatf("write on %s started at cycle %0d before previous write (M%0d) finished at %0d",
                       m.port_name, first, prev_wr_mgr + 1, prev_wr_stop))
        have_wr = 1; prev_wr_stop = m.b_cycle; prev_wr_mgr = m.agent_id;
    endfunction

    protected function void check_wr_decerr(axi4l_item m);
        n_wr++; n_decerr++; n_wr_m[m.agent_id]++;
        check_order_wr(m);
        if (m.resp != AXI4L_RESP_DECERR)
            `uvm_error("SB-DECERR", $sformatf("unmapped write must return DECERR: %s", m.convert2string()))
    endfunction

    protected function void check_wr_pair(axi4l_item m, axi4l_item s, int d);
        n_wr++; n_wr_m[m.agent_id]++; n_to_s[d]++;
        check_order_wr(m);
        if (m.addr !== s.addr)
            `uvm_error("SB-PASS", $sformatf("write address M %s -> S%0d: 0x%0h vs 0x%0h",
                       m.port_name, d + 1, m.addr, s.addr))
        if (m.data !== s.data)
            `uvm_error("SB-PASS", $sformatf("write data M %s -> S%0d: 0x%0h vs 0x%0h",
                       m.port_name, d + 1, m.data, s.data))
        if (m.resp !== s.resp)
            `uvm_error("SB-PASS", $sformatf("write resp S%0d -> M %s: %0b vs %0b",
                       d + 1, m.port_name, s.resp, m.resp))
        if (s.resp == AXI4L_RESP_OKAY) begin
            wr_rec_t r;
            int unsigned a = s.aw_cycle, w = s.w_cycle;
            r.start = (a < w) ? a : w;
            r.stop  = s.b_cycle;
            r.data  = s.data;
            wr_log[mkkey(d, cfg.word_addr(s.addr))].push_back(r);
        end
    endfunction

    // ------------------------------------------------------------- read checks
    protected function void check_order_rd(axi4l_item m);
        if (m.r_cycle <= m.ar_cycle)
            `uvm_error("SB-ORDER", $sformatf("R before/with AR: %s", m.convert2string()))
        if (have_rd && m.ar_cycle <= prev_rd_stop)
            `uvm_error("SB-LOCK", $sformatf("read on %s started at cycle %0d before previous read (M%0d) finished at %0d",
                       m.port_name, m.ar_cycle, prev_rd_mgr + 1, prev_rd_stop))
        have_rd = 1; prev_rd_stop = m.r_cycle; prev_rd_mgr = m.agent_id;
    endfunction

    protected function void check_rd_decerr(axi4l_item m);
        n_rd++; n_decerr++; n_rd_m[m.agent_id]++;
        check_order_rd(m);
        if (m.resp != AXI4L_RESP_DECERR)
            `uvm_error("SB-DECERR", $sformatf("unmapped read must return DECERR: %s", m.convert2string()))
        if (m.data !== '0)
            `uvm_error("SB-DECERR", $sformatf("unmapped read must return zero data: %s", m.convert2string()))
    endfunction

    protected function void check_rd_pair(axi4l_item m, axi4l_item s, int d);
        n_rd++; n_rd_m[m.agent_id]++; n_to_s[d]++;
        check_order_rd(m);
        if (m.addr !== s.addr)
            `uvm_error("SB-PASS", $sformatf("read address M %s -> S%0d: 0x%0h vs 0x%0h",
                       m.port_name, d + 1, m.addr, s.addr))
        if (m.data !== s.data)
            `uvm_error("SB-PASS", $sformatf("read data S%0d -> M %s: 0x%0h vs 0x%0h",
                       d + 1, m.port_name, s.data, m.data))
        if (m.resp !== s.resp)
            `uvm_error("SB-PASS", $sformatf("read resp S%0d -> M %s: %0b vs %0b",
                       d + 1, m.port_name, s.resp, m.resp))
        if (cfg.en_data_check && s.resp == AXI4L_RESP_OKAY) begin
            rd_rec_t r;
            r.dest = d; r.word = cfg.word_addr(m.addr); r.data = m.data;
            r.ar = m.ar_cycle; r.r = m.r_cycle;
            rd_chk.push_back(r);
        end
    endfunction

    // Read data is checked once all writes that could race with it have been reported.
    protected function void settle_reads(bit all);
        while (rd_chk.size() > 0 &&
               (all || max_cycle > rd_chk[0].r + cfg.settle_cycles)) begin
            rd_rec_t r = rd_chk.pop_front();
            check_shadow(r);
        end
    endfunction

    protected function void check_shadow(rd_rec_t r);
        key_t k = mkkey(r.dest, r.word);
        bit have = 0, race = 0;
        int unsigned best_stop = 0;
        axi4l_data_t exp = cfg.signature(r.dest) ^ axi4l_data_t'(r.word);
        int unsigned pz = 0;
        bit poisoned = 0;

        // latest reset that left this word unknown before the read
        if (poison.exists(k))
            foreach (poison[k][i])
                if (poison[k][i] < r.r && (!poisoned || poison[k][i] > pz)) begin poisoned = 1; pz = poison[k][i]; end

        if (wr_log.exists(k)) begin
            foreach (wr_log[k][i]) begin
                wr_rec_t w = wr_log[k][i];
                if (w.start <= r.r && w.stop >= r.ar) race = 1;    // write raced with the read (SW-5)
                else if (w.stop < r.ar && (!poisoned || w.start >= pz) &&
                         (!have || w.stop >= best_stop)) begin
                    have = 1; best_stop = w.stop; exp = w.data;
                end
            end
        end

        // word state unknown: racing write, or a write abandoned by reset with no newer write
        if (race || (poisoned && !have)) begin n_data_skip++; return; end
        n_data_chk++;
        if (r.data !== exp)
            `uvm_error("SB-DATA", $sformatf("S%0d word 0x%0h read 0x%0h, expected 0x%0h",
                       r.dest + 1, r.word, r.data, exp))
    endfunction

    // ------------------------------------------------------------------ end
    virtual function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        settle_reads(1);
        if (m_wr_q.size() + m_rd_q.size() > 0)
            `uvm_error("SB-LEFT", $sformatf("%0d write / %0d read M-side accesses never matched",
                       m_wr_q.size(), m_rd_q.size()))
        for (int i = 0; i < NS; i++)
            if (s_wr_q[i].size() + s_rd_q[i].size() > 0)
                `uvm_error("SB-LEFT", $sformatf("S%0d: %0d write / %0d read accesses with no M-side access",
                           i + 1, s_wr_q[i].size(), s_rd_q[i].size()))
    endfunction

    virtual function void report_phase(uvm_phase phase);
        string per_s = "";
        for (int i = 0; i < NS; i++) per_s = {per_s, $sformatf(" S%0d=%0d", i + 1, n_to_s[i])};
        `uvm_info("SB", $sformatf("writes=%0d (M1=%0d M2=%0d) reads=%0d (M1=%0d M2=%0d) decerr=%0d flushes=%0d",
                  n_wr, n_wr_m[0], n_wr_m[1], n_rd, n_rd_m[0], n_rd_m[1], n_decerr, n_flush), UVM_NONE)
        `uvm_info("SB", $sformatf("per-subordinate:%s", per_s), UVM_NONE)
        `uvm_info("SB", $sformatf("read data checks=%0d skipped(race/reset)=%0d", n_data_chk, n_data_skip), UVM_NONE)
    endfunction
endclass
