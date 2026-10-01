//=============================================================================
// File        : bridge_reset_mid_transfer_seq.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Coordinates the reset-during-transfer scenario with the
//               reactive AHB slave sequence.
//               Included inside bridge_seq_pkg.sv.
//=============================================================================

class bridge_reset_mid_transfer_seq extends bridge_base_seq;

    `uvm_object_utils(bridge_reset_mid_transfer_seq)

    //-------------------------------------------------------------------------
    // Sequence knobs
    //-------------------------------------------------------------------------
    bit [AXI4_ADDR_WIDTH-1:0] base_addr   = 'h1000;
    int unsigned              case_stride = 'h100;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "bridge_reset_mid_transfer_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Sequence body
    //-------------------------------------------------------------------------
    virtual task body();
        ahb_response_policy               policy;
        ahb_slv_response_mapping_seq      ahb_seq;
        axi4_mst_reset_mid_transfer_seq   axi_seq;

        require_axi_sequencer();
        require_ahb_sequencer();
        if (cfg.ahb_cfg.auto_gen_resp)
            `uvm_fatal(get_type_name(),
                       "Reset mid-transfer sequence requires auto_gen_resp = 0")
        if (!cfg.clear_queues_on_reset)
            `uvm_fatal(get_type_name(),
                       {"The queue reset hooks are what this test checks; ",
                        "clear_queues_on_reset must be set"})

        policy = ahb_response_policy::type_id::create("policy");

        ahb_seq        = ahb_slv_response_mapping_seq::type_id::create("ahb_seq");
        ahb_seq.policy = policy;

        axi_seq = axi4_mst_reset_mid_transfer_seq::type_id::create("axi_seq");
        axi_seq.policy      = policy;
        axi_seq.ahb_vif     = cfg.ahb_cfg.vif;
        axi_seq.base_addr   = base_addr;
        axi_seq.case_stride = case_stride;

        fork
            ahb_seq.start(p_sequencer.ahb_sqr);
        join_none

        axi_seq.start(p_sequencer.axi_sqr);
        ahb_seq.kill();
    endtask : body

endclass : bridge_reset_mid_transfer_seq