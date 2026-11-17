// AXI4-Lite UVC: slave (subordinate) driver. Autonomous responder with a word
// memory; connects to a DUT master port. It has no sequencer: behaviour is
// set by the agent cfg (delays, early READY, SLVERR injection).
//
// - AW and W are accepted independently, in either order; B is issued once both
//   have been accepted. Responses are held until accepted.
// - Unwritten words read back (signature ^ address) so a misrouted access is visible.
// - A write answered with SLVERR does not update the memory.
// - Reset aborts in-flight work but keeps the memory contents.

class axi4l_slave_driver extends uvm_component;
    `uvm_component_utils(axi4l_slave_driver)

    axi4l_agent_cfg cfg;
    axi4l_vif_t     vif;

    axi4l_data_t mem [axi4l_addr_t];
    int unsigned wr_count, rd_count, err_count;

    protected mailbox #(axi4l_addr_t) aw_mb;
    protected mailbox #(axi4l_data_t) w_mb;
    protected mailbox #(axi4l_addr_t) ar_mb;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        aw_mb = new();
        w_mb  = new();
        ar_mb = new();
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (cfg == null) `uvm_fatal("NOCFG", "agent cfg not set")
        vif = cfg.vif;
        if (vif == null) `uvm_fatal("NOVIF", "virtual interface not set in agent cfg")
    endfunction

    // ---- Memory (word aligned) --------------------------------------------
    function axi4l_addr_t word_addr(axi4l_addr_t a);
        localparam int LSB = $clog2(AXI4L_DATA_W / 8);
        return (a >> LSB) << LSB;
    endfunction

    function axi4l_data_t mem_read(axi4l_addr_t a);
        axi4l_addr_t w = word_addr(a);
        if (mem.exists(w)) return mem[w];
        return cfg.signature ^ axi4l_data_t'(w);
    endfunction

    function void mem_write(axi4l_addr_t a, axi4l_data_t d);
        mem[word_addr(a)] = d;
    endfunction

    function bit [1:0] pick_resp(axi4l_addr_t a);
        bit err = 0;
        if (cfg.err_win_en && a >= cfg.err_lo && a <= cfg.err_hi) err = 1;
        if (cfg.slverr_pct != 0 && $urandom_range(99) < cfg.slverr_pct) err = 1;
        return err ? AXI4L_RESP_SLVERR : AXI4L_RESP_OKAY;
    endfunction

    // ---- Main loop --------------------------------------------------------
    function void idle_outputs();
        vif.AWREADY <= 1'b0;
        vif.WREADY  <= 1'b0;
        vif.BVALID  <= 1'b0;
        vif.BRESP   <= '0;
        vif.ARREADY <= 1'b0;
        vif.RVALID  <= 1'b0;
        vif.RDATA   <= '0;
        vif.RRESP   <= '0;
    endfunction

    function void flush();
        axi4l_addr_t a;
        axi4l_data_t d;
        while (aw_mb.try_get(a));
        while (w_mb.try_get(d));
        while (ar_mb.try_get(a));
    endfunction

    virtual task run_phase(uvm_phase phase);
        idle_outputs();
        forever begin
            wait (vif.ARESETn === 1'b1);
            fork
                begin
                    fork
                        aw_thread();
                        w_thread();
                        b_thread();
                        ar_thread();
                        r_thread();
                    join
                end
                begin wait (vif.ARESETn !== 1'b1); end
            join_any
            disable fork;
            flush();
            idle_outputs();
        end
    endtask

    // ---- Address / data acceptance ----------------------------------------
    task aw_thread();
        axi4l_addr_t a;
        int unsigned d;
        forever begin
            d = axi4l_rand_dly(cfg.awready_dly);
            if (cfg.awready_early) begin
                vif.AWREADY <= 1'b1;
                do @(posedge vif.ACLK); while (vif.AWVALID !== 1'b1);
            end
            else begin
                do @(posedge vif.ACLK); while (vif.AWVALID !== 1'b1);
                repeat (d) @(posedge vif.ACLK);
                vif.AWREADY <= 1'b1;
                do @(posedge vif.ACLK); while (vif.AWVALID !== 1'b1);
            end
            a = vif.AWADDR;
            vif.AWREADY <= 1'b0;
            aw_mb.put(a);
        end
    endtask

    task w_thread();
        axi4l_data_t wd;
        int unsigned d;
        forever begin
            d = axi4l_rand_dly(cfg.wready_dly);
            if (cfg.wready_early) begin
                vif.WREADY <= 1'b1;
                do @(posedge vif.ACLK); while (vif.WVALID !== 1'b1);
            end
            else begin
                do @(posedge vif.ACLK); while (vif.WVALID !== 1'b1);
                repeat (d) @(posedge vif.ACLK);
                vif.WREADY <= 1'b1;
                do @(posedge vif.ACLK); while (vif.WVALID !== 1'b1);
            end
            wd = vif.WDATA;
            vif.WREADY <= 1'b0;
            w_mb.put(wd);
        end
    endtask

    task ar_thread();
        axi4l_addr_t a;
        int unsigned d;
        forever begin
            d = axi4l_rand_dly(cfg.arready_dly);
            if (cfg.arready_early) begin
                vif.ARREADY <= 1'b1;
                do @(posedge vif.ACLK); while (vif.ARVALID !== 1'b1);
            end
            else begin
                do @(posedge vif.ACLK); while (vif.ARVALID !== 1'b1);
                repeat (d) @(posedge vif.ACLK);
                vif.ARREADY <= 1'b1;
                do @(posedge vif.ACLK); while (vif.ARVALID !== 1'b1);
            end
            a = vif.ARADDR;
            vif.ARREADY <= 1'b0;
            ar_mb.put(a);
        end
    endtask

    // ---- Responses --------------------------------------------------------
    task b_thread();
        axi4l_addr_t a;
        axi4l_data_t wd;
        bit [1:0]    resp;
        forever begin
            aw_mb.get(a);
            w_mb.get(wd);
            resp = pick_resp(a);
            if (resp == AXI4L_RESP_OKAY) mem_write(a, wd);
            else                         err_count++;
            wr_count++;
            repeat (axi4l_rand_dly(cfg.b_dly)) @(posedge vif.ACLK);
            vif.BRESP  <= resp;
            vif.BVALID <= 1'b1;
            do @(posedge vif.ACLK); while (vif.BREADY !== 1'b1);
            vif.BVALID <= 1'b0;
            vif.BRESP  <= '0;
        end
    endtask

    task r_thread();
        axi4l_addr_t a;
        bit [1:0]    resp;
        forever begin
            ar_mb.get(a);
            resp = pick_resp(a);
            if (resp != AXI4L_RESP_OKAY) err_count++;
            rd_count++;
            repeat (axi4l_rand_dly(cfg.r_dly)) @(posedge vif.ACLK);
            vif.RDATA  <= mem_read(a);
            vif.RRESP  <= resp;
            vif.RVALID <= 1'b1;
            do @(posedge vif.ACLK); while (vif.RREADY !== 1'b1);
            vif.RVALID <= 1'b0;
            vif.RDATA  <= '0;
            vif.RRESP  <= '0;
        end
    endtask
endclass
