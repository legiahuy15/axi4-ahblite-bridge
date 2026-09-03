//=============================================================================
// File        : ahb_wrap_burst_test.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : Wrapping burst test. Runs ahb_wrap_burst_seq with WRAP4, WRAP8
//               and WRAP16 over all legal sizes, starting both on and inside
//               the wrap boundary.
//               Covers AHB_BST_006 to AHB_BST_008, AHB_BST_010 and AHB_DAT_006
//               in doc/ahb_lite_vplan.xlsx.
//               This file is `included inside ahb_test_pkg.sv.
//=============================================================================

`ifndef AHB_WRAP_BURST_TEST_INCLUDED_
`define AHB_WRAP_BURST_TEST_INCLUDED_

class ahb_wrap_burst_test extends ahb_base_test;

    `uvm_component_utils(ahb_wrap_burst_test)

    // Bursts to issue, overridable: +NUM_ITER=<n>
    int unsigned num_iter = 16;

    //-------------------------------------------------------------------------
    // Constructor
    //-------------------------------------------------------------------------
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction : new

    //-------------------------------------------------------------------------
    // Build phase - memory-model slave with a few wait states
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
        ahb_wrap_burst_seq seq;

        phase.raise_objection(this, "wrap burst test running");
        phase.phase_done.set_drain_time(this, 200ns);

        seq = ahb_wrap_burst_seq::type_id::create("seq");
        seq.num_iter = num_iter;
        seq.start(env.master_agent.sqr);

        phase.drop_objection(this, "wrap burst test done");
    endtask : run_phase

endclass : ahb_wrap_burst_test

`endif // AHB_WRAP_BURST_TEST_INCLUDED_