//=============================================================================
// File        : bridge_unsupported_feature_seq.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Coordinates the locked-request scenario (BRG_UNS_001).
//               Included inside bridge_seq_pkg.sv.
//=============================================================================

class bridge_unsupported_feature_seq extends bridge_base_seq;

    `uvm_object_utils(bridge_unsupported_feature_seq)

    //-------------------------------------------------------------------------
    // Sequence knobs
    //-------------------------------------------------------------------------
    bit [AXI4_ADDR_WIDTH-1:0] base_addr   = 'h1000;
    int unsigned              case_stride = 'h100;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "bridge_unsupported_feature_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Sequence body
    //-------------------------------------------------------------------------
    virtual task body();
        axi4_mst_lock_seq axi_seq;
        uvm_event         allow_lock_event;

        require_axi_sequencer();
        require_ahb_sequencer();
        if (!cfg.ahb_cfg.auto_gen_resp)
            `uvm_fatal(get_type_name(),
                       "Unsupported-feature sequence requires automatic AHB responses")

        // Locked traffic violates the legal-profile lock assertions
        allow_lock_event = uvm_event_pool::get_global("bridge_allow_lock");
        if (!allow_lock_event.is_on())
            `uvm_fatal(get_type_name(),
                       {"Locked requests need the lock-profile assertions ",
                        "disabled: trigger bridge_allow_lock in the test"})

        axi_seq = axi4_mst_lock_seq::type_id::create("axi_seq");
        axi_seq.base_addr   = base_addr;
        axi_seq.case_stride = case_stride;
        axi_seq.start(p_sequencer.axi_sqr);
    endtask : body

endclass : bridge_unsupported_feature_seq
