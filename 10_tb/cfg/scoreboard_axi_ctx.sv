//=============================================================================
// File        : scoreboard_axi_ctx.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Scoreboard context of one AXI request: predicted AHB beats
//               and the AXI completion rebuilt from observed beats.
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

    // Declared timeout: unissued beats are not counted as lost and the
    // completion is dropped instead of compared
    bit              timed_out;
    bit              response_dropped;

    // expect_timeout: must time out; allow_timeout: may time out, compared
    // normally if it completes
    bit              timeout_strict;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(axi4_transaction tr);
        this.tr = tr;
    endfunction : new

endclass : scoreboard_axi_ctx