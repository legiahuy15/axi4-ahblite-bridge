//=============================================================================
// File        : bridge_sanity_seq.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Coordinates the bridge sanity scenario.
//               Included inside bridge_seq_pkg.sv.
//=============================================================================

class bridge_sanity_seq extends bridge_base_seq;

    `uvm_object_utils(bridge_sanity_seq)

    //-------------------------------------------------------------------------
    // Sequence knobs
    //-------------------------------------------------------------------------
    int unsigned              num_iter    = 4;
    bit [AXI4_ADDR_WIDTH-1:0] base_addr   = 'h1000;
    int unsigned              addr_stride = AXI4_STRB_WIDTH;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "bridge_sanity_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Sequence body
    //-------------------------------------------------------------------------
    virtual task body();
        axi4_mst_sanity_seq axi_seq;

        require_axi_sequencer();
        require_ahb_sequencer();
        if (!cfg.ahb_cfg.auto_gen_resp)
            `uvm_fatal(get_type_name(),
                       "Sanity sequence requires automatic AHB responses")

        axi_seq = axi4_mst_sanity_seq::type_id::create("axi_seq");
        axi_seq.num_iter    = num_iter;
        axi_seq.base_addr   = base_addr;
        axi_seq.addr_stride = addr_stride;
        axi_seq.start(p_sequencer.axi_sqr);
    endtask : body

endclass : bridge_sanity_seq