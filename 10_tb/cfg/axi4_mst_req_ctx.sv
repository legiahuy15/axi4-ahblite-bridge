//=============================================================================
// File        : axi4_mst_req_ctx.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Internal request context for AXI4 master driver.
//=============================================================================

class axi4_mst_req_ctx;

    axi4_transaction tr;
    bit aw_done;
    bit w_started;

    function new(axi4_transaction tr);
        this.tr = tr;
    endfunction : new

endclass : axi4_mst_req_ctx