//=============================================================================
// File        : ahb_incr_burst_test.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : Incrementing burst test. Runs ahb_incr_burst_seq with INCR4,
//               INCR8 and INCR16 over all legal sizes, placing bursts up
//               against the 1KB boundary.
//               Covers AHB_BST_003 to AHB_BST_005, AHB_BST_009, AHB_BST_011
//               and AHB_BST_012 in doc/ahb_lite_vplan.xlsx.
//               This file is `included inside ahb_test_pkg.sv.
//=============================================================================

`ifndef AHB_INCR_BURST_TEST_INCLUDED_
`define AHB_INCR_BURST_TEST_INCLUDED_

class ahb_incr_burst_test extends ahb_base_test;

    `uvm_component_utils(ahb_incr_burst_test)

    // Bursts to issue, overridable: +NUM_ITER=<n>
    int unsigned num_iter = 16;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    //-------------------------------------------------------------------------
    // Build phase - memory-model slave with a few wait states, so beats see
    // both back-pressure and zero-wait completions
    //-------------------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        env_cfg.slave_agent_cfg.auto_gen_resp   = 1;
        env_cfg.slave_agent_cfg.ready_delay_min = 0;
        env_cfg.slave_agent_cfg.ready_delay_max = 2;

        void'($value$plusargs("NUM_ITER=%d", num_iter));
    endfunction : build_phase

    //-------------------------------------------------------------------------
    // Run phase
    //-------------------------------------------------------------------------
    task run_phase(uvm_phase phase);
        ahb_incr_burst_seq seq;

        phase.raise_objection(this, "incr burst test running");
        phase.phase_done.set_drain_time(this, 200ns);

        seq = ahb_incr_burst_seq::type_id::create("seq");
        seq.num_iter = num_iter;
        seq.start(env.master_agent.sqr);

        phase.drop_objection(this, "incr burst test done");
    endtask : run_phase

endclass : ahb_incr_burst_test

`endif // AHB_INCR_BURST_TEST_INCLUDED_