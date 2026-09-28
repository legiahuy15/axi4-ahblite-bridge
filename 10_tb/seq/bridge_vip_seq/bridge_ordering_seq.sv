//=============================================================================
// File        : bridge_ordering_seq.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Coordinates the completion ordering scenario. The AHB slave
//               answers from its memory model, so a read returns what an
//               earlier write left at that address and the order of the two
//               is visible in the data; no reactive slave sequence is
//               started. The slave configuration is handed over as well,
//               because the stimulus moves the AHB wait states from phase to
//               phase and the address pattern of an untouched word comes
//               from it.
//               Included inside bridge_seq_pkg.sv.
//=============================================================================

class bridge_ordering_seq extends bridge_base_seq;

    `uvm_object_utils(bridge_ordering_seq)

    //-------------------------------------------------------------------------
    // Sequence knobs
    //-------------------------------------------------------------------------
    bit [AXI4_ADDR_WIDTH-1:0] base_addr       = 'h2000;
    int unsigned              slot_bytes      = 'h100;
    int unsigned              stress_requests = 24;
    int unsigned              stress_slots    = 8;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "bridge_ordering_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Sequence body
    //-------------------------------------------------------------------------
    virtual task body();
        axi4_mst_ordering_seq axi_seq;

        require_axi_sequencer();
        if (!cfg.ahb_cfg.auto_gen_resp)
            `uvm_fatal(get_type_name(),
                       {"A read must return what an earlier write left ",
                        "behind; auto_gen_resp must be set"})
        if (!cfg.ahb_cfg.addr_pattern_read)
            `uvm_fatal(get_type_name(),
                       {"The expected word of an untouched address is the ",
                        "address pattern; addr_pattern_read must be set"})
        if (!cfg.is_valid())
            `uvm_fatal(get_type_name(),
                       "The environment configuration is not valid")

        axi_seq                 = axi4_mst_ordering_seq::type_id::create("axi_seq");
        axi_seq.ahb_cfg         = cfg.ahb_cfg;
        axi_seq.ahb_vif         = cfg.ahb_cfg.vif;
        axi_seq.base_addr       = base_addr;
        axi_seq.slot_bytes      = slot_bytes;
        axi_seq.stress_requests = stress_requests;
        axi_seq.stress_slots    = stress_slots;

        axi_seq.start(p_sequencer.axi_sqr);
    endtask : body

endclass : bridge_ordering_seq
