//==============================================================================
// File        : axi4_slave_sequencer.sv
// Project     : AXI4 VIP
// Author      : Huy Le
// Description : AXI4 slave sequencer.
//               Parameterised uvm_sequencer for axi4_transaction.
//               Reserved for future sequence-driven slave responses
//               (e.g., error injection, custom response patterns).
//               Currently unused - the slave driver operates in reactive mode.
//               This file is `included inside axi4_pkg.sv.
//==============================================================================

class axi4_slave_sequencer extends uvm_sequencer #(axi4_transaction);

    `uvm_component_utils(axi4_slave_sequencer)

    // =========================================================================
    // Constructor
    // =========================================================================
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

endclass : axi4_slave_sequencer