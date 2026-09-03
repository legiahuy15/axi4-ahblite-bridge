//=============================================================================
// File        : ahb_master_sequencer.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : AHB-Lite master sequencer. Feeds ahb_transaction items to the
//               master driver.
//=============================================================================

class ahb_master_sequencer extends uvm_sequencer #(ahb_transaction);

    `uvm_component_utils(ahb_master_sequencer)

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

endclass : ahb_master_sequencer