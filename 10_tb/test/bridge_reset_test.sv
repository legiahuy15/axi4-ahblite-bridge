//=============================================================================
// File        : bridge_reset_test.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Bridge synchronous reset test. Reset asserted at five points
//               in the clock cycle; outputs must take their reset values on
//               the next edge. Default build only.
//               Covers BRG_RST_002, BRG_RST_003, BRG_RST_004 and BRG_ATT_005.
//               Included inside the bridge test package.
//=============================================================================

class bridge_reset_test extends bridge_base_test;

    `uvm_component_utils(bridge_reset_test)

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
        // The long hold that parks the bus comes from the plan in the sequence
        env_cfg.ahb_cfg.auto_gen_resp      = 1'b0;
        env_cfg.ahb_cfg.clear_mem_on_reset = 1'b1;
        // Each case resets mid-run, so the predictor, scoreboard and coverage
        // must drop the request the reset discards
        env_cfg.clear_queues_on_reset      = 1'b1;

        void'($value$plusargs("BASE_ADDR=%h",   base_addr));
        void'($value$plusargs("CASE_STRIDE=%d", case_stride));
    endfunction : build_phase

    //-------------------------------------------------------------------------
    // Run phase
    //-------------------------------------------------------------------------
    task run_phase(uvm_phase phase);
        bridge_reset_seq seq;

        phase.raise_objection(this, "Bridge reset test started");

        seq = bridge_reset_seq::type_id::create("seq");
        seq.base_addr   = base_addr;
        seq.case_stride = case_stride;
        seq.start(env.vseqr);

        repeat (10) @(env_cfg.axi_cfg.vif.master_cb);
        phase.drop_objection(this, "Bridge reset test completed");
    endtask : run_phase

endclass : bridge_reset_test