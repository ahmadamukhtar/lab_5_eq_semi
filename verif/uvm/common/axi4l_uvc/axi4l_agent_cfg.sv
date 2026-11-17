// AXI4-Lite UVC: agent configuration (one object per agent instance).

class axi4l_agent_cfg extends uvm_object;

    // ---- Common -----------------------------------------------------------
    axi4l_vif_t            vif;
    axi4l_mode_e           mode           = AXI4L_MASTER;
    uvm_active_passive_enum is_active     = UVM_ACTIVE;   // PASSIVE: monitor only
    int unsigned           agent_id       = 0;
    string                 port_name      = "axi4l";
    int unsigned           timeout_cycles = 20000;        // per-item watchdog (master)
    bit                    idle_payload_random = 1;       // random AxADDR/WDATA/... while VALID is low

    // ---- Slave (subordinate) behaviour ------------------------------------
    axi4l_dly_t            awready_dly = '{min: 0, max: 0};  // VALID seen -> READY
    axi4l_dly_t            wready_dly  = '{min: 0, max: 0};
    axi4l_dly_t            arready_dly = '{min: 0, max: 0};
    bit                    awready_early = 0;                // READY held high before VALID
    bit                    wready_early  = 0;
    bit                    arready_early = 0;
    axi4l_dly_t            b_dly       = '{min: 0, max: 0};  // AW+W done -> BVALID
    axi4l_dly_t            r_dly       = '{min: 0, max: 0};  // AR done -> RVALID

    int unsigned           slverr_pct  = 0;                  // 0..100, random SLVERR
    bit                    err_win_en  = 0;                  // SLVERR for [err_lo:err_hi]
    axi4l_addr_t           err_lo      = '0;
    axi4l_addr_t           err_hi      = '0;
    axi4l_data_t           signature   = '0;                 // unwritten words read back signature ^ address

    `uvm_object_utils(axi4l_agent_cfg)

    function new(string name = "axi4l_agent_cfg");
        super.new(name);
    endfunction

    // Convenience: same delay range on every slave channel.
    function void set_slave_delays(int unsigned lo, int unsigned hi);
        awready_dly = '{min: lo, max: hi};
        wready_dly  = '{min: lo, max: hi};
        arready_dly = '{min: lo, max: hi};
        b_dly       = '{min: lo, max: hi};
        r_dly       = '{min: lo, max: hi};
    endfunction
endclass
