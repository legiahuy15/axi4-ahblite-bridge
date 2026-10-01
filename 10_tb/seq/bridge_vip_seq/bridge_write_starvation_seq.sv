//=============================================================================
// File        : bridge_write_starvation_seq.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Coordinates the write-data starvation scenario (AHB slave
//               answers from its memory model, no wait states).
//               Included inside bridge_seq_pkg.sv.
//=============================================================================

class bridge_write_starvation_seq extends bridge_base_seq;

    `uvm_object_utils(bridge_write_starvation_seq)

    //-------------------------------------------------------------------------
    // Sequence knobs
    //-------------------------------------------------------------------------
    bit [AXI4_ADDR_WIDTH-1:0] base_addr   = 'h8000;
    int unsigned              case_stride = 'h40;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "bridge_write_starvation_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Sequence body
    //-------------------------------------------------------------------------
    virtual task body();
        axi4_mst_write_starvation_seq axi_seq;

        require_axi_sequencer();
        if (!cfg.ahb_cfg.auto_gen_resp)
            `uvm_fatal(get_type_name(),
                       {"Every burst is read back afterwards, which needs ",
                        "the slave memory model; auto_gen_resp must be set"})
        if (!cfg.is_valid())
            `uvm_fatal(get_type_name(),
                       "The environment configuration is not valid")

        axi_seq             = axi4_mst_write_starvation_seq::type_id::create("axi_seq");
        axi_seq.ahb_vif     = cfg.ahb_cfg.vif;
        axi_seq.base_addr   = base_addr;
        axi_seq.case_stride = case_stride;

        axi_seq.start(p_sequencer.axi_sqr);
    endtask : body

endclass : bridge_write_starvation_seq
