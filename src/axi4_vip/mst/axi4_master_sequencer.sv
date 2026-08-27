//==============================================================================
// File        : axi4_master_sequencer.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : AXI4 master sequencer.
//               Parameterised uvm_sequencer for axi4_transaction.
//               Sequences generate write/read transactions that are passed
//               to the master driver for driving onto the AXI4 bus.
//               This file is `included inside axi4_pkg.sv.
//==============================================================================

class axi4_master_sequencer extends uvm_sequencer #(axi4_transaction);

    `uvm_component_utils(axi4_master_sequencer)

    // =========================================================================
    // Constructor
    // =========================================================================
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

endclass : axi4_master_sequencer