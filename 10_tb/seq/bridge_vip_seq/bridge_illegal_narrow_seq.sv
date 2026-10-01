//=============================================================================
// File        : bridge_illegal_narrow_seq.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Coordinates the unsupported-write scenario (AHB slave
//               answers from its memory model).
//               Included inside bridge_seq_pkg.sv.
//=============================================================================

class bridge_illegal_narrow_seq extends bridge_base_seq;

    `uvm_object_utils(bridge_illegal_narrow_seq)

    //-------------------------------------------------------------------------
    // Sequence knobs
    //-------------------------------------------------------------------------
    bit [AXI4_ADDR_WIDTH-1:0] base_addr   = 'hA000;
    int unsigned              case_stride = 'h80;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "bridge_illegal_narrow_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Sequence body
    //-------------------------------------------------------------------------
    virtual task body();
        ahb_response_policy        pattern;
        axi4_mst_illegal_narrow_seq axi_seq;

        require_axi_sequencer();
        if (!cfg.ahb_cfg.auto_gen_resp)
            `uvm_fatal(get_type_name(),
                       {"These cases are judged on what they leave in ",
                        "memory; auto_gen_resp must be set"})
        if (!cfg.ahb_cfg.addr_pattern_read)
            `uvm_fatal(get_type_name(),
                       {"An untouched word must return its address pattern; ",
                        "addr_pattern_read must be set"})
        if (!cfg.is_valid())
            `uvm_fatal(get_type_name(),
                       "The environment configuration is not valid")

        pattern = ahb_response_policy::type_id::create("pattern");

        axi_seq                 = axi4_mst_illegal_narrow_seq::type_id::create("axi_seq");
        axi_seq.pattern         = pattern;
        axi_seq.base_addr       = base_addr;
        axi_seq.case_stride     = case_stride;
        axi_seq.supports_narrow = cfg.supports_narrow_burst;

        axi_seq.start(p_sequencer.axi_sqr);
    endtask : body

endclass : bridge_illegal_narrow_seq
