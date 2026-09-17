//=============================================================================
// File        : bridge_incr_mapping_seq.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Coordinates the bridge INCR burst mapping scenario.
//               Included inside bridge_seq_pkg.sv.
//=============================================================================

class bridge_incr_mapping_seq extends bridge_base_seq;

    `uvm_object_utils(bridge_incr_mapping_seq)

    //-------------------------------------------------------------------------
    // Sequence knobs
    //-------------------------------------------------------------------------
    bit [AXI4_ADDR_WIDTH-1:0] base_addr     = 'h1000;
    int unsigned              case_stride   = 'h400;
    bit                       enable_narrow = 1'b0;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "bridge_incr_mapping_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Sequence body
    //-------------------------------------------------------------------------
    virtual task body();
        axi4_mst_incr_mapping_seq axi_seq;

        require_axi_sequencer();
        require_ahb_sequencer();
        if (!cfg.ahb_cfg.auto_gen_resp)
            `uvm_fatal(get_type_name(),
                       "INCR mapping sequence requires automatic AHB responses")
        // Narrow single transfers are outside the supported profile unless
        // the DUT is built with narrow support (PG177 Narrow Transfers)
        if (enable_narrow && !cfg.supports_narrow_burst)
            `uvm_fatal(get_type_name(),
                       {"Narrow cases require a DUT built with ",
                        "C_S_AXI_SUPPORTS_NARROW_BURST=1"})

        axi_seq = axi4_mst_incr_mapping_seq::type_id::create("axi_seq");
        axi_seq.base_addr     = base_addr;
        axi_seq.case_stride   = case_stride;
        axi_seq.enable_narrow = enable_narrow;
        axi_seq.start(p_sequencer.axi_sqr);
    endtask : body

endclass : bridge_incr_mapping_seq