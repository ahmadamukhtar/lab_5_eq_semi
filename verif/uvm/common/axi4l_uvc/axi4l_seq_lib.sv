// AXI4-Lite UVC: sequence library.
// Run write sequences on agent.wr_sqr and read sequences on agent.rd_sqr; the
// two directions can run concurrently.

class axi4l_write_seq extends uvm_sequence #(axi4l_item);
    rand axi4l_addr_t addr;
    rand axi4l_data_t data;
    bit               no_delay = 1;    // 1: back-to-back, in order; 0: randomise the timing knobs
    int unsigned      start_delay = 0; // no_delay=1 only: cycles before AWVALID/WVALID
    axi4l_item        result;          // completed item (resp, aborted, ...)

    `uvm_object_utils(axi4l_write_seq)

    function new(string name = "axi4l_write_seq");
        super.new(name);
    endfunction

    virtual task body();
        axi4l_item it = axi4l_item::type_id::create("wr_item");
        start_item(it);
        if (!it.randomize() with { kind == AXI4L_WRITE;
                                   addr == local::addr;
                                   data == local::data; })
            `uvm_fatal("RAND", "axi4l_write_seq randomize failed")
        if (no_delay) begin
            it.set_no_delay();
            it.aw_delay = start_delay;
            it.w_delay  = start_delay;
        end
        finish_item(it);
        result = it;
    endtask
endclass

class axi4l_read_seq extends uvm_sequence #(axi4l_item);
    rand axi4l_addr_t addr;
    bit               no_delay = 1;
    int unsigned      start_delay = 0; // no_delay=1 only: cycles before ARVALID
    axi4l_item        result;          // result.data / result.resp hold the read result

    `uvm_object_utils(axi4l_read_seq)

    function new(string name = "axi4l_read_seq");
        super.new(name);
    endfunction

    virtual task body();
        axi4l_item it = axi4l_item::type_id::create("rd_item");
        start_item(it);
        if (!it.randomize() with { kind == AXI4L_READ;
                                   addr == local::addr; })
            `uvm_fatal("RAND", "axi4l_read_seq randomize failed")
        if (no_delay) begin
            it.set_no_delay();
            it.ar_delay = start_delay;
        end
        finish_item(it);
        result = it;
    endtask
endclass

// Random writes with random timing; optional address window.
class axi4l_wr_rand_seq extends uvm_sequence #(axi4l_item);
    rand int unsigned num_items = 10;
    axi4l_addr_t      addr_lo   = '0;
    axi4l_addr_t      addr_hi   = '1;

    constraint c_num { num_items inside {[1:1000]}; }

    `uvm_object_utils(axi4l_wr_rand_seq)

    function new(string name = "axi4l_wr_rand_seq");
        super.new(name);
    endfunction

    virtual task body();
        repeat (num_items) begin
            axi4l_item it = axi4l_item::type_id::create("wr_item");
            start_item(it);
            if (!it.randomize() with { kind == AXI4L_WRITE;
                                       addr inside {[local::addr_lo : local::addr_hi]}; })
                `uvm_fatal("RAND", "axi4l_wr_rand_seq randomize failed")
            finish_item(it);
        end
    endtask
endclass

// Random reads with random timing; optional address window.
class axi4l_rd_rand_seq extends uvm_sequence #(axi4l_item);
    rand int unsigned num_items = 10;
    axi4l_addr_t      addr_lo   = '0;
    axi4l_addr_t      addr_hi   = '1;

    constraint c_num { num_items inside {[1:1000]}; }

    `uvm_object_utils(axi4l_rd_rand_seq)

    function new(string name = "axi4l_rd_rand_seq");
        super.new(name);
    endfunction

    virtual task body();
        repeat (num_items) begin
            axi4l_item it = axi4l_item::type_id::create("rd_item");
            start_item(it);
            if (!it.randomize() with { kind == AXI4L_READ;
                                       addr inside {[local::addr_lo : local::addr_hi]}; })
                `uvm_fatal("RAND", "axi4l_rd_rand_seq randomize failed")
            finish_item(it);
        end
    endtask
endclass
