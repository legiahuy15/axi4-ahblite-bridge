//=============================================================================
// File        : axi4_mst_sequencer.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : AXI4 master sequencer.
//               Included inside the bridge package.
//=============================================================================

class axi4_mst_sequencer extends uvm_sequencer #(axi4_transaction);

    `uvm_component_utils(axi4_mst_sequencer)

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

endclass : axi4_mst_sequencer