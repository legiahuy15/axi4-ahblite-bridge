//=============================================================================
// File        : bridge_1kb_boundary_seq.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Coordinates the bridge 1 KB boundary scenario.
//               Included inside bridge_seq_pkg.sv.
//=============================================================================

class bridge_1kb_boundary_seq extends bridge_base_seq;

    `uvm_object_utils(bridge_1kb_boundary_seq)

    //-------------------------------------------------------------------------
    // Sequence knobs
    //-------------------------------------------------------------------------
    bit [AXI4_ADDR_WIDTH-1:0] page_base = 'h10000;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "bridge_1kb_boundary_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Sequence body
    //-------------------------------------------------------------------------
    virtual task body();
        axi4_mst_1kb_boundary_seq axi_seq;

        require_axi_sequencer();
        require_ahb_sequencer();
        if (!cfg.ahb_cfg.auto_gen_resp)
            `uvm_fatal(get_type_name(),
                       "1KB boundary sequence requires automatic AHB responses")

        axi_seq = axi4_mst_1kb_boundary_seq::type_id::create("axi_seq");
        axi_seq.page_base = page_base;
        axi_seq.start(p_sequencer.axi_sqr);
    endtask : body

endclass : bridge_1kb_boundary_seq