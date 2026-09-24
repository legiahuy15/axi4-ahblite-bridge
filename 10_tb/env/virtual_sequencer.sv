//=============================================================================
// File        : virtual_sequencer.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Coordinates AXI4 stimulus and AHB-Lite responses.
//               Included inside the bridge package.
//=============================================================================

class virtual_sequencer extends uvm_sequencer;

    `uvm_component_utils(virtual_sequencer)

    //-------------------------------------------------------------------------
    // Configuration and agent handles
    //-------------------------------------------------------------------------
    vip_env_cfg        cfg;
    axi4_mst_sequencer axi_sqr;
    ahb_slv_sequencer  ahb_sqr;

    // Null when the environment runs without a scoreboard. A sequence that
    // declares a watchdog timeout needs it (see scoreboard::expect_timeout).
    scoreboard         scb;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

endclass : virtual_sequencer