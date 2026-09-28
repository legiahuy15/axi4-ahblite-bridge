//=============================================================================
// File        : bridge_random_stress_seq.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Coordinates the constrained-random regression scenario.
//               Starts the reactive AHB slave sequence and shares one
//               response policy with the AXI stimulus, which is what lets
//               the wait and error decisions be drawn on their own rather
//               than being derived from the request they answer.
//               Included inside bridge_seq_pkg.sv.
//=============================================================================

class bridge_random_stress_seq extends bridge_base_seq;

    `uvm_object_utils(bridge_random_stress_seq)

    //-------------------------------------------------------------------------
    // Sequence knobs
    //-------------------------------------------------------------------------
    bit [AXI4_ADDR_WIDTH-1:0] base_addr     = 'h4000;
    int unsigned              window_bytes  = 'h4000;
    int unsigned              num_requests  = 64;
    int unsigned              error_percent = 12;
    int unsigned              max_wait      = 4;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name = "bridge_random_stress_seq");
        super.new(name);
    endfunction : new

    //-------------------------------------------------------------------------
    // Sequence body
    //-------------------------------------------------------------------------
    virtual task body();
        ahb_response_policy            policy;
        ahb_slv_response_mapping_seq   ahb_seq;
        axi4_mst_random_stress_seq     axi_seq;

        require_axi_sequencer();
        require_ahb_sequencer();
        if (cfg.ahb_cfg.auto_gen_resp)
            `uvm_fatal(get_type_name(),
                       {"The wait and error policy is drawn by the ",
                        "stimulus; auto_gen_resp must be 0"})
        if (!cfg.is_valid())
            `uvm_fatal(get_type_name(),
                       "The environment configuration is not valid")

        policy = ahb_response_policy::type_id::create("policy");

        ahb_seq        = ahb_slv_response_mapping_seq::type_id::create("ahb_seq");
        ahb_seq.policy = policy;

        axi_seq                 = axi4_mst_random_stress_seq::type_id::create("axi_seq");
        axi_seq.policy          = policy;
        axi_seq.base_addr       = base_addr;
        axi_seq.window_bytes    = window_bytes;
        axi_seq.num_requests    = num_requests;
        axi_seq.error_percent   = error_percent;
        axi_seq.max_wait        = max_wait;
        axi_seq.supports_narrow = cfg.supports_narrow_burst;

        fork
            ahb_seq.start(p_sequencer.ahb_sqr);
        join_none

        axi_seq.start(p_sequencer.axi_sqr);
        ahb_seq.kill();
    endtask : body

endclass : bridge_random_stress_seq