// AXI4-Lite UVC: master driver (acts as a manager; connects to a DUT slave port).
//
// Write and read directions run as independent threads, each fed by its own
// sequencer, and each handles one item at a time (single outstanding).
// Signals are sampled at the clock edge (pre-edge values) and driven with
// non-blocking assignments, so they change together with DUT registers.
// An asynchronous reset aborts the in-flight item and returns the outputs to idle.

class axi4l_master_driver extends uvm_driver #(axi4l_item);
    `uvm_component_utils(axi4l_master_driver)

    // seq_item_port serves the write sequencer; this one serves the read sequencer.
    uvm_seq_item_pull_port #(axi4l_item) rd_seq_item_port;

    axi4l_agent_cfg cfg;
    axi4l_vif_t     vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        rd_seq_item_port = new("rd_seq_item_port", this);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (cfg == null) `uvm_fatal("NOCFG", "agent cfg not set")
        vif = cfg.vif;
        if (vif == null) `uvm_fatal("NOVIF", "virtual interface not set in agent cfg")
    endfunction

    virtual task run_phase(uvm_phase phase);
        idle_write();
        idle_read();
        fork
            write_loop();
            read_loop();
        join
    endtask

    // ---- Idle values ------------------------------------------------------
    function axi4l_addr_t idle_addr();
        return cfg.idle_payload_random ? axi4l_rand_addr() : '0;
    endfunction

    function axi4l_data_t idle_data();
        return cfg.idle_payload_random ? axi4l_rand_data() : '0;
    endfunction

    function void idle_write();
        vif.AWVALID <= 1'b0;
        vif.AWADDR  <= idle_addr();
        vif.WVALID  <= 1'b0;
        vif.WDATA   <= idle_data();
        vif.BREADY  <= 1'b0;
    endfunction

    function void idle_read();
        vif.ARVALID <= 1'b0;
        vif.ARADDR  <= idle_addr();
        vif.RREADY  <= 1'b0;
    endfunction

    task wait_reset_released();
        if (vif.ARESETn !== 1'b1) begin
            wait (vif.ARESETn === 1'b1);
            @(posedge vif.ACLK);
        end
    endtask

    // ---- Write direction --------------------------------------------------
    task write_loop();
        axi4l_item it;
        forever begin
            seq_item_port.get_next_item(it);
            wait_reset_released();
            if (it.kind != AXI4L_WRITE)
                `uvm_error("KIND", $sformatf("read item on the write sequencer: %s", it.convert2string()))
            else
                guarded_write(it);
            seq_item_port.item_done();
        end
    endtask

    task guarded_write(axi4l_item it);
        bit rst_hit = 0;
        bit tmo     = 0;
        it.agent_id  = cfg.agent_id;
        it.port_name = cfg.port_name;
        fork begin
            fork
                drive_write(it);
                begin @(negedge vif.ARESETn); rst_hit = 1; end
                begin repeat (cfg.timeout_cycles) @(posedge vif.ACLK); tmo = 1; end
            join_any
            disable fork;
        end join
        if (rst_hit || tmo) begin
            idle_write();
            it.aborted   = rst_hit;
            it.timed_out = tmo;
            if (tmo)
                `uvm_error("TIMEOUT", $sformatf("write did not complete in %0d cycles: %s",
                                                cfg.timeout_cycles, it.convert2string()))
            else
                `uvm_info("RESET", $sformatf("write aborted by reset: %s", it.convert2string()), UVM_MEDIUM)
        end
        else
            `uvm_info("DRV", $sformatf("done %s", it.convert2string()), UVM_HIGH)
    endtask

    task drive_write(axi4l_item it);
        fork
            begin : aw_ch
                repeat (it.aw_delay + 1) @(posedge vif.ACLK);
                vif.AWADDR  <= it.addr;
                vif.AWVALID <= 1'b1;
                do @(posedge vif.ACLK); while (vif.AWREADY !== 1'b1);
                vif.AWVALID <= 1'b0;
                vif.AWADDR  <= idle_addr();
            end
            begin : w_ch
                repeat (it.w_delay + 1) @(posedge vif.ACLK);
                vif.WDATA  <= it.data;
                vif.WVALID <= 1'b1;
                do @(posedge vif.ACLK); while (vif.WREADY !== 1'b1);
                vif.WVALID <= 1'b0;
                vif.WDATA  <= idle_data();
            end
            begin : b_ch
                if (it.resp_ready_early) begin
                    @(posedge vif.ACLK);
                    vif.BREADY <= 1'b1;
                    do @(posedge vif.ACLK); while (vif.BVALID !== 1'b1);
                end
                else begin
                    do @(posedge vif.ACLK); while (vif.BVALID !== 1'b1);
                    repeat (it.bready_delay) @(posedge vif.ACLK);
                    vif.BREADY <= 1'b1;
                    do @(posedge vif.ACLK); while (vif.BVALID !== 1'b1);
                end
                it.resp = vif.BRESP;
                vif.BREADY <= 1'b0;
            end
        join
    endtask

    // ---- Read direction ---------------------------------------------------
    task read_loop();
        axi4l_item it;
        forever begin
            rd_seq_item_port.get_next_item(it);
            wait_reset_released();
            if (it.kind != AXI4L_READ)
                `uvm_error("KIND", $sformatf("write item on the read sequencer: %s", it.convert2string()))
            else
                guarded_read(it);
            rd_seq_item_port.item_done();
        end
    endtask

    task guarded_read(axi4l_item it);
        bit rst_hit = 0;
        bit tmo     = 0;
        it.agent_id  = cfg.agent_id;
        it.port_name = cfg.port_name;
        fork begin
            fork
                drive_read(it);
                begin @(negedge vif.ARESETn); rst_hit = 1; end
                begin repeat (cfg.timeout_cycles) @(posedge vif.ACLK); tmo = 1; end
            join_any
            disable fork;
        end join
        if (rst_hit || tmo) begin
            idle_read();
            it.aborted   = rst_hit;
            it.timed_out = tmo;
            if (tmo)
                `uvm_error("TIMEOUT", $sformatf("read did not complete in %0d cycles: %s",
                                                cfg.timeout_cycles, it.convert2string()))
            else
                `uvm_info("RESET", $sformatf("read aborted by reset: %s", it.convert2string()), UVM_MEDIUM)
        end
        else
            `uvm_info("DRV", $sformatf("done %s", it.convert2string()), UVM_HIGH)
    endtask

    task drive_read(axi4l_item it);
        fork
            begin : ar_ch
                repeat (it.ar_delay + 1) @(posedge vif.ACLK);
                vif.ARADDR  <= it.addr;
                vif.ARVALID <= 1'b1;
                do @(posedge vif.ACLK); while (vif.ARREADY !== 1'b1);
                vif.ARVALID <= 1'b0;
                vif.ARADDR  <= idle_addr();
            end
            begin : r_ch
                if (it.resp_ready_early) begin
                    @(posedge vif.ACLK);
                    vif.RREADY <= 1'b1;
                    do @(posedge vif.ACLK); while (vif.RVALID !== 1'b1);
                end
                else begin
                    do @(posedge vif.ACLK); while (vif.RVALID !== 1'b1);
                    repeat (it.rready_delay) @(posedge vif.ACLK);
                    vif.RREADY <= 1'b1;
                    do @(posedge vif.ACLK); while (vif.RVALID !== 1'b1);
                end
                it.data = vif.RDATA;
                it.resp = vif.RRESP;
                vif.RREADY <= 1'b0;
            end
        join
    endtask
endclass
