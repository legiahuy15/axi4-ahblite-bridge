//=============================================================================
// File        : bridge_mutation_seq.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Coordinates the scoreboard fault-injection suite.
//               Included inside bridge_seq_pkg.sv.
//=============================================================================

class bridge_mutation_seq extends bridge_base_seq;

    `uvm_object_utils(bridge_mutation_seq)

    //-------------------------------------------------------------------------
    // Sequence knobs
    //-------------------------------------------------------------------------
    bit [AXI4_ADDR_WIDTH-1:0] base_addr   = 'hC000;
    int unsigned              case_stride = 'h40;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "bridge_mutation_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Sequence body
    //-------------------------------------------------------------------------
    virtual task body();
        axi4_mst_mutation_seq axi_seq;

        require_axi_sequencer();
        if (p_sequencer.scb == null)
            `uvm_fatal(get_type_name(),
                       {"There is nothing to test without the scoreboard; ",
                        "has_scoreboard must be set"})
        if (!cfg.is_valid())
            `uvm_fatal(get_type_name(),
                       "The environment configuration is not valid")

        axi_seq             = axi4_mst_mutation_seq::type_id::create("axi_seq");
        axi_seq.scb         = p_sequencer.scb;
        axi_seq.base_addr   = base_addr;
        axi_seq.case_stride = case_stride;

        axi_seq.start(p_sequencer.axi_sqr);
    endtask : body

endclass : bridge_mutation_seq
