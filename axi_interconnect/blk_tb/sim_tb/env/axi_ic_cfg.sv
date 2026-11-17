// Interconnect env configuration: address map and agent delay profiles.

class axi_ic_cfg extends uvm_object;
    localparam int NUM_M = 2;
    localparam int NUM_S = 9;

    // Window i: (addr & mask[i]) == (base[i] & mask[i]); lowest index wins.
    axi4l_addr_t base [NUM_S];
    axi4l_addr_t mask [NUM_S];

    // Master-side / slave-side default behaviour
    int unsigned slave_dly_min = 0;
    int unsigned slave_dly_max = 0;
    int unsigned slverr_pct    = 0;

    `uvm_object_utils(axi_ic_cfg)

    function new(string name = "axi_ic_cfg");
        super.new(name);
        // Default map: nine 4 KiB windows from 0x0000_0000.
        for (int i = 0; i < NUM_S; i++) begin
            base[i] = axi4l_addr_t'(i * 32'h1000);
            mask[i] = ~axi4l_addr_t'(32'h0000_0FFF);
        end
    endfunction

    // Behavioural model of slave i's memory: unwritten words read back signature ^ word address.
    function axi4l_data_t signature(int i);
        return axi4l_data_t'(32'h1111_0000 * (i + 1));
    endfunction

    function axi4l_addr_t word_addr(axi4l_addr_t a);
        localparam int LSB = $clog2(AXI4L_DATA_W / 8);
        return (a >> LSB) << LSB;
    endfunction

    // Scoreboard knobs
    bit          en_data_check  = 1;   // read data vs shadow memory
    int unsigned max_wait_cycles = 16; // M-side vs S-side pairing window
    int unsigned settle_cycles   = 100;// delay before a read is checked against the shadow

    // Returns the index of the matching window, or -1 on a decode miss.
    function int decode(axi4l_addr_t a);
        for (int i = 0; i < NUM_S; i++)
            if ((a & mask[i]) == (base[i] & mask[i])) return i;
        return -1;
    endfunction
endclass
