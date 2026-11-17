// AXI4-Lite UVC: transaction item.
// One item is one single-beat write (AW+W+B) or one read (AR+R).
// The same class is used for stimulus (master sequences) and for the
// transactions published by the monitor.

class axi4l_item extends uvm_sequence_item;

    // ---- Request ----------------------------------------------------------
    rand axi4l_kind_e kind;
    rand axi4l_addr_t addr;
    rand axi4l_data_t data;          // write data (request) / read data (result)

    // ---- Master-side timing knobs (cycles) ---------------------------------
    rand axi4l_wr_order_e order;
    rand int unsigned     aw_delay;      // before AWVALID
    rand int unsigned     w_delay;       // before WVALID
    rand int unsigned     ar_delay;      // before ARVALID
    rand int unsigned     bready_delay;  // BVALID seen -> BREADY
    rand int unsigned     rready_delay;  // RVALID seen -> RREADY
    rand bit              resp_ready_early; // BREADY/RREADY raised before VALID

    // ---- Result -----------------------------------------------------------
    bit [1:0]    resp;
    bit          aborted;      // reset hit while the item was in flight
    bit          timed_out;

    // ---- Monitor annotations ----------------------------------------------
    int unsigned agent_id;
    string       port_name;
    int unsigned aw_cycle, w_cycle, b_cycle, ar_cycle, r_cycle;   // handshake cycles
    int unsigned req_cycle;   // first cycle AWVALID (write) / ARVALID (read) was seen high
    int unsigned rsp_cycle;   // first cycle BVALID (write) / RVALID (read) was seen high

    `uvm_object_utils_begin(axi4l_item)
        `uvm_field_enum(axi4l_kind_e, kind, UVM_ALL_ON)
        `uvm_field_int(addr, UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(data, UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(resp, UVM_ALL_ON | UVM_BIN)
        `uvm_field_int(aborted, UVM_ALL_ON | UVM_NOPRINT)
        `uvm_field_int(timed_out, UVM_ALL_ON | UVM_NOPRINT)
        `uvm_field_int(agent_id, UVM_ALL_ON | UVM_NOPRINT | UVM_NOCOMPARE)
        `uvm_field_string(port_name, UVM_ALL_ON | UVM_NOPRINT | UVM_NOCOMPARE)
        `uvm_field_int(aw_cycle, UVM_ALL_ON | UVM_NOPRINT | UVM_NOCOMPARE)
        `uvm_field_int(w_cycle, UVM_ALL_ON | UVM_NOPRINT | UVM_NOCOMPARE)
        `uvm_field_int(b_cycle, UVM_ALL_ON | UVM_NOPRINT | UVM_NOCOMPARE)
        `uvm_field_int(ar_cycle, UVM_ALL_ON | UVM_NOPRINT | UVM_NOCOMPARE)
        `uvm_field_int(r_cycle, UVM_ALL_ON | UVM_NOPRINT | UVM_NOCOMPARE)
    `uvm_object_utils_end

    constraint c_addr_aligned {
        soft addr[1:0] == 2'b00;
    }

    constraint c_order {
        soft order dist {AXI4L_ORDER_SAME := 40, AXI4L_ORDER_AW_FIRST := 30, AXI4L_ORDER_W_FIRST := 30};
        (order == AXI4L_ORDER_AW_FIRST) -> (aw_delay <  w_delay);
        (order == AXI4L_ORDER_W_FIRST)  -> (w_delay  <  aw_delay);
        (order == AXI4L_ORDER_SAME)     -> (aw_delay == w_delay);
    }

    constraint c_delays {
        soft aw_delay      dist {0 := 50, [1:3] := 35, [4:12] := 15};
        soft w_delay       dist {0 := 50, [1:3] := 35, [4:12] := 15};
        soft ar_delay      dist {0 := 50, [1:3] := 35, [4:12] := 15};
        soft bready_delay  dist {0 := 50, [1:3] := 35, [4:12] := 15};
        soft rready_delay  dist {0 := 50, [1:3] := 35, [4:12] := 15};
        aw_delay     <= 64;
        w_delay      <= 64;
        ar_delay     <= 64;
        bready_delay <= 64;
        rready_delay <= 64;
        soft resp_ready_early dist {0 := 70, 1 := 30};
    }

    function new(string name = "axi4l_item");
        super.new(name);
    endfunction

    // Zero-delay, in-order stimulus; handy for directed sequences.
    function void set_no_delay();
        aw_delay = 0; w_delay = 0; ar_delay = 0;
        bready_delay = 0; rready_delay = 0;
        resp_ready_early = 0;
        order = AXI4L_ORDER_SAME;
    endfunction

    virtual function string convert2string();
        string s;
        if (kind == AXI4L_WRITE)
            s = $sformatf("%s WR addr=0x%0h data=0x%0h resp=%0b", port_name, addr, data, resp);
        else
            s = $sformatf("%s RD addr=0x%0h data=0x%0h resp=%0b", port_name, addr, data, resp);
        if (aborted)   s = {s, " [ABORTED]"};
        if (timed_out) s = {s, " [TIMEOUT]"};
        return s;
    endfunction
endclass
