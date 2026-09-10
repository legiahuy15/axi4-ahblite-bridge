//=============================================================================
// File        : bridge_wrap_mapping_test.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Bridge WRAP burst mapping directed test.
//               Checks WRAP2 expansion and WRAP4/8/16 address behavior
//               across every legal wrap offset.
//               Covers BRG_BST_007 to BRG_BST_010.
//               Included inside the bridge test package.
//=============================================================================

class bridge_wrap_mapping_test extends bridge_base_test;

    `uvm_component_utils(bridge_wrap_mapping_test)

    //-------------------------------------------------------------------------
    // Test knobs
    //-------------------------------------------------------------------------
    bit [AXI4_ADDR_WIDTH-1:0] base_addr = 'h1000;

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

        void'($value$plusargs("BASE_ADDR=%h", base_addr));
    endfunction : build_phase

    //-------------------------------------------------------------------------
    // Run phase
    //-------------------------------------------------------------------------
    task run_phase(uvm_phase phase);
        bridge_wrap_mapping_seq seq;

        phase.raise_objection(this, "Bridge WRAP mapping test started");

        seq = bridge_wrap_mapping_seq::type_id::create("seq");
        seq.base_addr = base_addr;
        seq.start(env.vseqr);

        repeat (10) @(env_cfg.axi_cfg.vif.master_cb);
        phase.drop_objection(this, "Bridge WRAP mapping test completed");
    endtask : run_phase

endclass : bridge_wrap_mapping_test