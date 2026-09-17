//=============================================================================
// File        : scoreboard_axi_ctx.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Per-request context for scoreboard reconstruction: the
//               predicted AHB beats of one AXI request and the AXI
//               completion rebuilt from the AHB beats observed for it.
//               Included inside the bridge package.
//=============================================================================

class scoreboard_axi_ctx;

    //-------------------------------------------------------------------------
    // Context fields
    //-------------------------------------------------------------------------
    axi4_transaction tr;
    ahb_transfer     expected_beats[$];  // predicted beats not yet matched
    bit              started;            // an observed AHB beat was matched
    int unsigned     beat_index;
    bit              write_error;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(axi4_transaction tr);
        this.tr = tr;
    endfunction : new

endclass : scoreboard_axi_ctx