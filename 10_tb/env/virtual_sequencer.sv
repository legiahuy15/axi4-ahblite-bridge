//=============================================================================
// File        : virtual_sequencer.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Coordinates AXI4 stimulus and AHB-Lite responses.
//               Included inside the bridge package.
//=============================================================================

// Forward declaration (included before scoreboard.sv)
typedef class scoreboard;

class virtual_sequencer extends uvm_sequencer;

    `uvm_component_utils(virtual_sequencer)

    //-------------------------------------------------------------------------
    // Configuration and agent handles
    //-------------------------------------------------------------------------
    vip_env_cfg        cfg;
    axi4_mst_sequencer axi_sqr;
    ahb_slv_sequencer  ahb_sqr;

    // Null without a scoreboard; needed to declare timeouts
    scoreboard         scb;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

endclass : virtual_sequencer