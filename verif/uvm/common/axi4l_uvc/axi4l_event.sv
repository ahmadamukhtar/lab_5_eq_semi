// AXI4-Lite UVC: per-handshake event published by the monitor.
// Used by scoreboards/checkers that need ordering and timing (arbitration,
// grant lock, latency) rather than complete transactions.

class axi4l_event extends uvm_object;
    axi4l_event_e ev;
    int unsigned  cycle;      // monitor clock-cycle counter at the handshake
    time          sim_time;
    int unsigned  agent_id;
    string        port_name;
    axi4l_addr_t  addr;       // AW / AR
    axi4l_data_t  data;       // W / R
    bit [1:0]     resp;       // B / R

    `uvm_object_utils(axi4l_event)

    function new(string name = "axi4l_event");
        super.new(name);
    endfunction

    virtual function string convert2string();
        return $sformatf("%s %s cycle=%0d addr=0x%0h data=0x%0h resp=%0b",
                         port_name, ev.name(), cycle, addr, data, resp);
    endfunction
endclass
