//=============================================================================
// File        : bridge_fixed_mapping_seq.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Coordinates the bridge FIXED burst mapping scenario.
//               Included inside bridge_seq_pkg.sv.
//=============================================================================

class bridge_fixed_mapping_seq extends bridge_base_seq;

    `uvm_object_utils(bridge_fixed_mapping_seq)

    //-------------------------------------------------------------------------
    // Sequence knobs
    //-------------------------------------------------------------------------
    bit [AXI4_ADDR_WIDTH-1:0] base_addr     = 'h1000;
    int unsigned              case_stride   = 'h100;
    int unsigned              random_cases  = 4;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "bridge_fixed_mapping_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Sequence body
    //-------------------------------------------------------------------------
    virtual task body();
        axi4_mst_fixed_mapping_seq axi_seq;

        require_axi_sequencer();
        require_ahb_sequencer();
        if (!cfg.ahb_cfg.auto_gen_resp)
            `uvm_fatal(get_type_name(),
                       "FIXED mapping sequence requires automatic AHB responses")

        axi_seq = axi4_mst_fixed_mapping_seq::type_id::create("axi_seq");
        axi_seq.base_addr    = base_addr;
        axi_seq.case_stride  = case_stride;
        axi_seq.random_cases = random_cases;
        axi_seq.start(p_sequencer.axi_sqr);
    endtask : body

endclass : bridge_fixed_mapping_seq