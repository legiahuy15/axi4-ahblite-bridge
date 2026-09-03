//=============================================================================
// File        : predictor_req_entry.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Timestamped AXI request entry for predictor scheduling.
//               Included inside the bridge package.
//=============================================================================

class predictor_req_entry;

    //-------------------------------------------------------------------------
    // Entry fields
    //-------------------------------------------------------------------------
    axi4_transaction tr;
    time             timestamp;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(axi4_transaction tr, time timestamp);
        this.tr        = tr;
        this.timestamp = timestamp;
    endfunction : new

endclass : predictor_req_entry