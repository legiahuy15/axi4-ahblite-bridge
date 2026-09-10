//=============================================================================
// File        : bridge_fixed_mapping_test.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Bridge FIXED burst mapping directed test.
//               Checks repeated AHB SINGLE/NONSEQ expansion at a
//               constant address for AXI FIXED lengths 1, 16 and
//               random intermediates.
//               Covers BRG_BST_006.
//               Included inside the bridge test package.
//=============================================================================

class bridge_fixed_mapping_test extends bridge_base_test;

    `uvm_component_utils(bridge_fixed_mapping_test)

    //-------------------------------------------------------------------------
    // Test knobs
    //-------------------------------------------------------------------------
    bit [AXI4_ADDR_WIDTH-1:0] base_addr     = 'h1000;
    int unsigned              case_stride   = 'h100;
    int unsigned              random_cases  = 4;

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

        void'($value$plusargs("BASE_ADDR=%h",    base_addr));
        void'($value$plusargs("CASE_STRIDE=%d",  case_stride));
        void'($value$plusargs("RANDOM_CASES=%d", random_cases));
    endfunction : build_phase

    //-------------------------------------------------------------------------
    // Run phase
    //-------------------------------------------------------------------------
    task run_phase(uvm_phase phase);
        bridge_fixed_mapping_seq seq;

        phase.raise_objection(this, "Bridge FIXED mapping test started");

        seq = bridge_fixed_mapping_seq::type_id::create("seq");
        seq.base_addr    = base_addr;
        seq.case_stride  = case_stride;
        seq.random_cases = random_cases;
        seq.start(env.vseqr);

        repeat (10) @(env_cfg.axi_cfg.vif.master_cb);
        phase.drop_objection(this, "Bridge FIXED mapping test completed");
    endtask : run_phase

endclass : bridge_fixed_mapping_test