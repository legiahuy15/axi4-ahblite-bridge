//=============================================================================
// File        : ahb_slave_response.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : AHB-Lite slave response for one data phase.
//               Included after ahb_types.sv in the bridge package.
//=============================================================================

class ahb_slave_response extends uvm_sequence_item;

    // OKAY wait cycles; the driver adds the first ERROR response cycle.
    rand int unsigned         ready_delay;
    rand ahb_resp_e           resp;
    rand bit [AHB_DATA_WIDTH-1:0] rdata;

    //-------------------------------------------------------------------------
    // UVM utility macro
    //-------------------------------------------------------------------------
    `uvm_object_utils_begin(ahb_slave_response)
        `uvm_field_int(              ready_delay, UVM_ALL_ON)
        `uvm_field_enum(ahb_resp_e,  resp,        UVM_ALL_ON)
        `uvm_field_int(              rdata,       UVM_ALL_ON)
    `uvm_object_utils_end

    //-------------------------------------------------------------------------
    // Constraints
    //-------------------------------------------------------------------------
    constraint c_defaults {
        soft ready_delay == 0;
        soft resp        == AHB_RESP_OKAY;
    }

    constraint c_ready_delay {
        ready_delay <= 1024;
    }

    //-------------------------------------------------------------------------
    // Constructors
    //-------------------------------------------------------------------------
    function new(string name = "ahb_slave_response");
        super.new(name);
        if (!(AHB_DATA_WIDTH inside {32, 64}))
            `uvm_fatal("AHB_CFG", $sformatf("Illegal AHB_DATA_WIDTH=%0d", AHB_DATA_WIDTH))
    endfunction : new

    //-------------------------------------------------------------------------
    // Supporters
    //-------------------------------------------------------------------------
    function string convert2string();
        return $sformatf("AHB slave resp=%s waits=%0d rdata=0x%0h",
                         resp.name(), ready_delay, rdata);
    endfunction : convert2string

endclass : ahb_slave_response