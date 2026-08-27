//=============================================================================
// File        : ahb_slave_sequencer.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : AHB-Lite slave sequencer. Feeds ahb_slave_response items to the
//               slave driver. Used only in sequence mode (auto_gen_resp = 0).
//=============================================================================

class ahb_slave_sequencer extends uvm_sequencer #(ahb_slave_response);

    `uvm_component_utils(ahb_slave_sequencer)

    //-------------------------------------------------------------------------
    // Address phase the driver is about to answer, published just before it
    // asks for an item. Readable by a response sequence between start_item()
    // and finish_item()
    //-------------------------------------------------------------------------
    bit [AHB_ADDR_WIDTH-1:0] req_addr;
    ahb_dir_e                req_write;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

endclass : ahb_slave_sequencer