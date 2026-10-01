//=============================================================================
// File        : bridge_unsupported_feature_test.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Bridge locked-request test: normal completion, no EXOKAY,
//               HMASTLOCK follows AxLOCK (lock assertions off).
//               Covers BRG_UNS_001.
//               Included inside the bridge test package.
//=============================================================================

class bridge_unsupported_feature_test extends bridge_base_test;

    `uvm_component_utils(bridge_unsupported_feature_test)

    //-------------------------------------------------------------------------
    // Test knobs
    //-------------------------------------------------------------------------
    bit [AXI4_ADDR_WIDTH-1:0] base_addr   = 'h1000;
    int unsigned              case_stride = 'h100;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    //-------------------------------------------------------------------------
    // Build phase
    //-------------------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        env_cfg.axi_cfg.return_responses = 1'b1;
        env_cfg.axi_cfg.max_outstanding  = 1;
        env_cfg.ahb_cfg.auto_gen_resp    = 1'b1;
        env_cfg.ahb_cfg.ready_delay_min  = 0;
        env_cfg.ahb_cfg.ready_delay_max  = 0;
        env_cfg.ahb_cfg.clear_mem_on_reset = 1'b1;

        void'($value$plusargs("BASE_ADDR=%h",   base_addr));
        void'($value$plusargs("CASE_STRIDE=%d", case_stride));
    endfunction : build_phase

    //-------------------------------------------------------------------------
    // Run phase
    //-------------------------------------------------------------------------
    task run_phase(uvm_phase phase);
        bridge_unsupported_feature_seq seq;
        uvm_event                      allow_lock_event;

        phase.raise_objection(this, "Bridge unsupported-feature test started");

        // Turn off LOCK_UNSUPPORTED, ARLOCK_UNSUPPORTED and NO_LOCK
        allow_lock_event = uvm_event_pool::get_global("bridge_allow_lock");
        allow_lock_event.trigger();

        seq = bridge_unsupported_feature_seq::type_id::create("seq");
        seq.base_addr   = base_addr;
        seq.case_stride = case_stride;
        seq.start(env.vseqr);

        repeat (10) @(env_cfg.axi_cfg.vif.master_cb);
        phase.drop_objection(this, "Bridge unsupported-feature test completed");
    endtask : run_phase

endclass : bridge_unsupported_feature_test