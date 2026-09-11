//=============================================================================
// File        : bridge_1kb_boundary_test.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Bridge 1 KB boundary directed test.
//               Exercises no-cross, exact-edge and crossing INCR cases
//               for both read and write.
//               Covers BRG_1KB_001 to BRG_1KB_004.
//               Included inside the bridge test package.
//=============================================================================

class bridge_1kb_boundary_test extends bridge_base_test;

    `uvm_component_utils(bridge_1kb_boundary_test)

    //-------------------------------------------------------------------------
    // Test knobs
    //-------------------------------------------------------------------------
    bit [AXI4_ADDR_WIDTH-1:0] page_base = 'h10000;

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

        void'($value$plusargs("PAGE_BASE=%h", page_base));
    endfunction : build_phase

    //-------------------------------------------------------------------------
    // Run phase
    //-------------------------------------------------------------------------
    task run_phase(uvm_phase phase);
        bridge_1kb_boundary_seq seq;

        phase.raise_objection(this, "Bridge 1KB boundary test started");

        seq = bridge_1kb_boundary_seq::type_id::create("seq");
        seq.page_base = page_base;
        seq.start(env.vseqr);

        repeat (10) @(env_cfg.axi_cfg.vif.master_cb);
        phase.drop_objection(this, "Bridge 1KB boundary test completed");
    endtask : run_phase

endclass : bridge_1kb_boundary_test