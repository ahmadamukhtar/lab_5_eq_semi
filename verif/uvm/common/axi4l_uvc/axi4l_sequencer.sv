// AXI4-Lite UVC: sequencer. A master agent has two (write and read) so that
// the two directions progress independently, as the bus allows.

class axi4l_sequencer extends uvm_sequencer #(axi4l_item);
    `uvm_component_utils(axi4l_sequencer)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
endclass
