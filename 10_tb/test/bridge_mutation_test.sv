//=============================================================================
// File        : bridge_mutation_test.sv
// Project     : AXI4 to AHB-Lite Bridge VIP
// Author      : Huy Le
// Description : Scoreboard fault-injection test. Corrupts one compared field
//               at a time and requires every fault to be caught. ID and
//               assertions are not covered.
//               Covers BRG_ENV_006.
//               Included inside the bridge test package.
//=============================================================================

class bridge_mutation_test extends bridge_base_test;

    `uvm_component_utils(bridge_mutation_test)

    //-------------------------------------------------------------------------
    // Test knobs
    //-------------------------------------------------------------------------
    bit [AXI4_ADDR_WIDTH-1:0] base_addr   = 'hC000;
    int unsigned              case_stride = 'h40;

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
        // Nothing about the traffic should vary: a case that behaves
        // differently has to differ because of its fault
        env_cfg.ahb_cfg.auto_gen_resp   = 1'b1;
        env_cfg.ahb_cfg.ready_delay_min = 0;
        env_cfg.ahb_cfg.ready_delay_max = 0;

        void'($value$plusargs("BASE_ADDR=%h",   base_addr));
        void'($value$plusargs("CASE_STRIDE=%d", case_stride));
    endfunction : build_phase

    //-------------------------------------------------------------------------
    // Run phase
    //-------------------------------------------------------------------------
    task run_phase(uvm_phase phase);
        bridge_mutation_seq seq;

        phase.raise_objection(this, "Bridge mutation test started");

        seq = bridge_mutation_seq::type_id::create("seq");
        seq.base_addr   = base_addr;
        seq.case_stride = case_stride;
        seq.start(env.vseqr);

        repeat (10) @(env_cfg.axi_cfg.vif.master_cb);
        phase.drop_objection(this, "Bridge mutation test completed");
    endtask : run_phase

endclass : bridge_mutation_test
