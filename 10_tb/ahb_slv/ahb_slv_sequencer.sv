//=============================================================================
// File        : ahb_slv_sequencer.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : AHB-Lite slave response sequencer.
//               Included inside the bridge package.
//=============================================================================

class ahb_slv_sequencer extends uvm_sequencer #(ahb_slave_response);

    `uvm_component_utils(ahb_slv_sequencer)

    //-------------------------------------------------------------------------
    // Current request
    //-------------------------------------------------------------------------
    // Address phase currently awaiting a response item
    ahb_transfer req;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

endclass : ahb_slv_sequencer