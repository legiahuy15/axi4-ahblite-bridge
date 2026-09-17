//=============================================================================
// File        : bridge_incr_mapping_test.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Bridge INCR burst mapping directed test.
//               Checks SINGLE, INCR4/8/16 and undefined-INCR selection
//               across every legal AxSIZE without 1 KB crossing.
//               Covers BRG_BST_001 to BRG_BST_005.
//               Included inside the bridge test package.
//=============================================================================

class bridge_incr_mapping_test extends bridge_base_test;

    `uvm_component_utils(bridge_incr_mapping_test)

    //-------------------------------------------------------------------------
    // Test knobs
    //-------------------------------------------------------------------------
    bit [AXI4_ADDR_WIDTH-1:0] base_addr    = 'h1000;
    int unsigned              case_stride  = 'h400;
    bit                       enable_narrow;  // follows DUT narrow support

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

        enable_narrow = env_cfg.supports_narrow_burst;
        void'($value$plusargs("BASE_ADDR=%h",     base_addr));
        void'($value$plusargs("CASE_STRIDE=%d",   case_stride));
        void'($value$plusargs("ENABLE_NARROW=%d", enable_narrow));
    endfunction : build_phase

    //-------------------------------------------------------------------------
    // Run phase
    //-------------------------------------------------------------------------
    task run_phase(uvm_phase phase);
        bridge_incr_mapping_seq seq;

        phase.raise_objection(this, "Bridge INCR mapping test started");

        seq = bridge_incr_mapping_seq::type_id::create("seq");
        seq.base_addr     = base_addr;
        seq.case_stride   = case_stride;
        seq.enable_narrow = enable_narrow;
        seq.start(env.vseqr);

        repeat (10) @(env_cfg.axi_cfg.vif.master_cb);
        phase.drop_objection(this, "Bridge INCR mapping test completed");
    endtask : run_phase

endclass : bridge_incr_mapping_test