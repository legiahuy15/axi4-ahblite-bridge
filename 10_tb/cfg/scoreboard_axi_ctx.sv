//=============================================================================
// File        : scoreboard_axi_ctx.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : AXI completion context for scoreboard reconstruction.
//               Included inside the bridge package.
//=============================================================================

class scoreboard_axi_ctx;

    //-------------------------------------------------------------------------
    // Context fields
    //-------------------------------------------------------------------------
    axi4_transaction tr;
    int unsigned     beat_index;
    bit              write_error;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(axi4_transaction tr);
        this.tr = tr;
    endfunction : new

endclass : scoreboard_axi_ctx