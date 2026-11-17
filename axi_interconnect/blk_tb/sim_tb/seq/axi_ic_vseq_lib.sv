// Interconnect virtual sequences. All run on axi_ic_vseqr.
//
//   axi_ic_base_vseq     helpers (wr/rd, address generators)
//   axi_ic_sweep_vseq    every manager x every subordinate, first/middle/last word, cross-manager readback
//   axi_ic_decode_vseq   window boundaries and unmapped addresses (DECERR)
//   axi_ic_arb_vseq      simultaneous and staggered requests from both managers
//   axi_ic_conc_vseq     read and write in flight together (same / different manager and target)
//   axi_ic_stress_vseq   4 concurrent random threads, random slave and manager timing
//   axi_ic_reset_vseq    stress traffic with mid-test reset pulses, then a sweep

class axi_ic_base_vseq extends uvm_sequence;
    `uvm_object_utils(axi_ic_base_vseq)
    `uvm_declare_p_sequencer(axi_ic_vseqr)

    function new(string name = "axi_ic_base_vseq");
        super.new(name);
    endfunction

    // ---- single accesses ---------------------------------------------------
    task wr(int m, axi4l_addr_t a, axi4l_data_t d, output bit [1:0] resp,
            input bit no_delay = 1, input int unsigned dly = 0);
        axi4l_write_seq s = axi4l_write_seq::type_id::create("wr");
        s.addr = a; s.data = d; s.no_delay = no_delay; s.start_delay = dly;
        s.start(p_sequencer.m_wr_sqr[m]);
        resp = s.result.resp;
    endtask

    task rd(int m, axi4l_addr_t a, output axi4l_data_t d, output bit [1:0] resp,
            input bit no_delay = 1, input int unsigned dly = 0);
        axi4l_read_seq s = axi4l_read_seq::type_id::create("rd");
        s.addr = a; s.no_delay = no_delay; s.start_delay = dly;
        s.start(p_sequencer.m_rd_sqr[m]);
        d    = s.result.data;
        resp = s.result.resp;
    endtask

    // ---- address generators -------------------------------------------------
    function axi4l_addr_t mapped_addr(int d, int word = -1);
        int w = (word >= 0) ? word : $urandom_range(1023, 0);
        return p_sequencer.cfg.base[d] + axi4l_addr_t'(w * 4);
    endfunction

    function axi4l_addr_t unmapped_addr();
        axi4l_addr_t top = p_sequencer.cfg.base[axi_ic_cfg::NUM_S-1] + 32'h1000;
        case ($urandom_range(2, 0))
            0: return top + axi4l_addr_t'($urandom_range(255, 0) * 4);
            1: return top + axi4l_addr_t'($urandom_range(32'hFFFF, 0) & ~3);
            default: return ~axi4l_addr_t'(3) - axi4l_addr_t'($urandom_range(15, 0) * 4);
        endcase
    endfunction

    // A small word set per slave so reads hit previously written data.
    function axi4l_addr_t hot_addr(int d);
        return mapped_addr(d, $urandom_range(7, 0) * 128);
    endfunction

    task wr_check_resp(int m, axi4l_addr_t a, axi4l_data_t d, bit [1:0] exp);
        bit [1:0] r;
        wr(m, a, d, r);
        if (r !== exp) `uvm_error("VSEQ", $sformatf("write 0x%0h resp %0b, expected %0b", a, r, exp))
    endtask

    task rd_check(int m, axi4l_addr_t a, bit [1:0] exp_resp, input bit check_val = 0,
                  input axi4l_data_t exp_val = '0);
        axi4l_data_t d; bit [1:0] r;
        rd(m, a, d, r);
        if (r !== exp_resp)
            `uvm_error("VSEQ", $sformatf("read 0x%0h resp %0b, expected %0b", a, r, exp_resp))
        if (check_val && d !== exp_val)
            `uvm_error("VSEQ", $sformatf("read 0x%0h data 0x%0h, expected 0x%0h", a, d, exp_val))
    endtask
endclass

// ---------------------------------------------------------------------------
class axi_ic_sweep_vseq extends axi_ic_base_vseq;
    `uvm_object_utils(axi_ic_sweep_vseq)
    function new(string name = "axi_ic_sweep_vseq"); super.new(name); endfunction

    virtual task body();
        int words[3] = '{0, 512, 1023};
        for (int m = 0; m < axi_ic_cfg::NUM_M; m++)
            for (int s = 0; s < axi_ic_cfg::NUM_S; s++)
                foreach (words[k]) begin
                    axi4l_addr_t a = mapped_addr(s, words[k]);
                    axi4l_data_t d;
                    case ((m + s + k) % 5)       // corner data patterns, then random
                        0: d = '0;
                        1: d = '1;
                        2: d = {(AXI4L_DATA_W/8){8'h5A}};
                        3: d = {(AXI4L_DATA_W/8){8'hA5}};
                        default: d = axi4l_rand_data();
                    endcase
                    wr_check_resp(m, a, d, AXI4L_RESP_OKAY);
                    // read back through both managers
                    rd_check(m,     a, AXI4L_RESP_OKAY, 1, d);
                    rd_check(1 - m, a, AXI4L_RESP_OKAY, 1, d);
                end
        // default memory pattern of an untouched word
        for (int s = 0; s < axi_ic_cfg::NUM_S; s++) begin
            axi4l_addr_t a = mapped_addr(s, 100);
            rd_check(s % 2, a, AXI4L_RESP_OKAY, 1,
                     p_sequencer.cfg.signature(s) ^ axi4l_data_t'(a));
        end
    endtask
endclass

// ---------------------------------------------------------------------------
class axi_ic_decode_vseq extends axi_ic_base_vseq;
    `uvm_object_utils(axi_ic_decode_vseq)
    function new(string name = "axi_ic_decode_vseq"); super.new(name); endfunction

    virtual task body();
        axi4l_data_t d; bit [1:0] r;
        // boundaries: last word of window i, first word of window i+1
        for (int i = 0; i < axi_ic_cfg::NUM_S; i++) begin
            axi4l_addr_t last = mapped_addr(i, 1023);
            wr_check_resp(i % 2, last, 32'hB0B0_0000 + i, AXI4L_RESP_OKAY);
            rd_check((i + 1) % 2, last, AXI4L_RESP_OKAY, 1, 32'hB0B0_0000 + i);
            if (i + 1 < axi_ic_cfg::NUM_S) begin
                axi4l_addr_t first = mapped_addr(i + 1, 0);
                wr_check_resp(i % 2, first, 32'hF0F0_0000 + i, AXI4L_RESP_OKAY);
                rd_check(i % 2, first, AXI4L_RESP_OKAY, 1, 32'hF0F0_0000 + i);
            end
        end
        // unmapped: just above the map, far above, top of the address space
        for (int m = 0; m < axi_ic_cfg::NUM_M; m++) begin
            axi4l_addr_t top = mapped_addr(axi_ic_cfg::NUM_S-1, 0) + 32'h1000;
            wr_check_resp(m, top,                32'hDEAD_0001, AXI4L_RESP_DECERR);
            rd_check(m,      top,                AXI4L_RESP_DECERR, 1, '0);
            wr_check_resp(m, top + 32'h4,        32'hDEAD_0002, AXI4L_RESP_DECERR);
            rd_check(m,      ~axi4l_addr_t'(3),  AXI4L_RESP_DECERR, 1, '0);
            wr_check_resp(m, ~axi4l_addr_t'(3),  32'hDEAD_0003, AXI4L_RESP_DECERR);
            repeat (10) begin
                axi4l_addr_t u = unmapped_addr();
                wr_check_resp(m, u, axi4l_rand_data(), AXI4L_RESP_DECERR);
                rd_check(m, u, AXI4L_RESP_DECERR, 1, '0);
            end
        end
        // an unmapped write must not disturb a mapped write that follows
        wr_check_resp(0, unmapped_addr(), 32'h1, AXI4L_RESP_DECERR);
        wr_check_resp(1, mapped_addr(3, 5), 32'hC0DE_0003, AXI4L_RESP_OKAY);
        rd_check(0, mapped_addr(3, 5), AXI4L_RESP_OKAY, 1, 32'hC0DE_0003);
        // unmapped accesses with random timing
        wr(0, unmapped_addr(), 32'h2, r, 0);
        rd(1, unmapped_addr(), d, r, 0);
    endtask
endclass

// ---------------------------------------------------------------------------
class axi_ic_arb_vseq extends axi_ic_base_vseq;
    `uvm_object_utils(axi_ic_arb_vseq)
    int unsigned rounds = 40;
    function new(string name = "axi_ic_arb_vseq"); super.new(name); endfunction

    virtual task body();
        repeat (rounds) begin
            int s0 = $urandom_range(8, 0), s1 = $urandom_range(8, 0);
            int unsigned d0 = $urandom_range(3, 0), d1 = $urandom_range(3, 0);
            bit [1:0] r0, r1;
            axi4l_data_t v0 = axi4l_rand_data(), v1 = axi4l_rand_data(), q0, q1;
            // both managers write (start offset 0..3 cycles), then both read
            fork
                wr(0, hot_addr(s0), v0, r0, 1, d0);
                wr(1, hot_addr(s1), v1, r1, 1, d1);
            join
            fork
                rd(0, hot_addr(s0), q0, r0, 1, d1);
                rd(1, hot_addr(s1), q1, r1, 1, d0);
            join
            // same target, equal start: the grant must still serialise them
            fork
                wr(0, hot_addr(s0), axi4l_rand_data(), r0, 1, 0);
                wr(1, hot_addr(s0), axi4l_rand_data(), r1, 1, 0);
            join
            fork
                rd(0, mapped_addr(s0, 0), q0, r0, 1, 0);
                rd(1, mapped_addr(s1, 0), q1, r1, 1, 0);
            join
        end
        // contention with random manager response stalls
        repeat (rounds) begin
            bit [1:0] r0, r1, r2, r3; axi4l_data_t q0, q1;
            fork
                wr(0, hot_addr($urandom_range(8, 0)), axi4l_rand_data(), r0, 0);
                wr(1, hot_addr($urandom_range(8, 0)), axi4l_rand_data(), r1, 0);
                rd(0, hot_addr($urandom_range(8, 0)), q0, r2, 0);
                rd(1, hot_addr($urandom_range(8, 0)), q1, r3, 0);
            join
        end
    endtask
endclass

// ---------------------------------------------------------------------------
class axi_ic_conc_vseq extends axi_ic_base_vseq;
    `uvm_object_utils(axi_ic_conc_vseq)
    int unsigned rounds = 40;
    function new(string name = "axi_ic_conc_vseq"); super.new(name); endfunction

    virtual task body();
        for (int wm = 0; wm < 2; wm++)
            for (int rm = 0; rm < 2; rm++)
                repeat (rounds / 4) begin
                    int ws = $urandom_range(8, 0);
                    int rs = ($urandom_range(1, 0)) ? ws : $urandom_range(8, 0);   // same or different target
                    bit [1:0] r0, r1; axi4l_data_t q;
                    fork
                        wr(wm, hot_addr(ws), axi4l_rand_data(), r0, $urandom_range(1, 0), $urandom_range(3, 0));
                        rd(rm, hot_addr(rs), q, r1, $urandom_range(1, 0), $urandom_range(3, 0));
                    join
                end
    endtask
endclass

// ---------------------------------------------------------------------------
class axi_ic_stress_vseq extends axi_ic_base_vseq;
    `uvm_object_utils(axi_ic_stress_vseq)
    int unsigned num_items     = 200;   // per thread; +NUM_ITEMS overrides
    int unsigned unmapped_pct  = 10;
    bit          random_slaves = 1;
    bit          use_plusarg   = 1;

    function new(string name = "axi_ic_stress_vseq"); super.new(name); endfunction

    function axi4l_addr_t pick_addr();
        if ($urandom_range(99, 0) < unmapped_pct) return unmapped_addr();
        return hot_addr($urandom_range(8, 0));
    endfunction

    task wr_thread(int m, int unsigned n);
        repeat (n) begin
            bit [1:0] r;
            wr(m, pick_addr(), axi4l_rand_data(), r, 0);
        end
    endtask

    task rd_thread(int m, int unsigned n);
        repeat (n) begin
            bit [1:0] r; axi4l_data_t q;
            rd(m, pick_addr(), q, r, 0);
        end
    endtask

    // New random behaviour on every subordinate.
    task randomise_slaves();
        foreach (p_sequencer.s_cfg[i]) begin
            axi4l_agent_cfg c = p_sequencer.s_cfg[i];
            int unsigned hi = $urandom_range(6, 0);
            c.set_slave_delays($urandom_range(hi, 0), hi);
            c.awready_early = $urandom_range(1, 0);
            c.wready_early  = $urandom_range(1, 0);
            c.arready_early = $urandom_range(1, 0);
            c.slverr_pct    = ($urandom_range(2, 0) == 0) ? $urandom_range(30, 0) : 0;
        end
    endtask

    virtual task body();
        if (use_plusarg) void'($value$plusargs("NUM_ITEMS=%d", num_items));
        if (random_slaves) randomise_slaves();
        fork
            wr_thread(0, num_items);
            wr_thread(1, num_items);
            rd_thread(0, num_items);
            rd_thread(1, num_items);
        join
    endtask
endclass

// ---------------------------------------------------------------------------
class axi_ic_reset_vseq extends axi_ic_stress_vseq;
    `uvm_object_utils(axi_ic_reset_vseq)
    int unsigned num_resets = 4;
    function new(string name = "axi_ic_reset_vseq"); super.new(name); endfunction

    virtual task body();
        axi_ic_sweep_vseq sw = axi_ic_sweep_vseq::type_id::create("sw");
        num_items   = 60;
        use_plusarg = 0;
        fork
            super.body();
            begin
                repeat (num_resets) begin
                    repeat ($urandom_range(80, 20)) @(posedge p_sequencer.rst_vif.ACLK);
                    p_sequencer.rst_vif.pulse($urandom_range(5, 2));
                end
            end
        join
        foreach (p_sequencer.s_cfg[i]) p_sequencer.s_cfg[i].slverr_pct = 0;
        // Everything must still work, and written data must read back.
        sw.start(p_sequencer);
    endtask
endclass
