//=============================================================================
// File        : ahb_single_transfer_test.sv
// Project     : AMBA 3 AHB-Lite VIP
// Author      : Huy Le
// Description : Randomized SINGLE transfer test. Runs ahb_single_seq over all
//               legal sizes, alignments and directions.
//               Covers AHB_BST_001 and AHB_TRN_007 in doc/ahb_lite_vplan.xlsx.
//               This file is `included inside ahb_test_pkg.sv.
//=============================================================================

`ifndef AHB_SINGLE_TRANSFER_TEST_INCLUDED_
`define AHB_SINGLE_TRANSFER_TEST_INCLUDED_

class ahb_single_transfer_test extends ahb_base_test;

    `uvm_component_utils(ahb_single_transfer_test)

    // Transfers to issue, overridable: +NUM_ITER=<n>
    int unsigned num_iter = 20;

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
        ahb_single_seq seq;

        phase.raise_objection(this, "single transfer test running");
        phase.phase_done.set_drain_time(this, 200ns);

        seq = ahb_single_seq::type_id::create("seq");
        seq.num_iter = num_iter;
        seq.start(env.master_agent.sqr);

        phase.drop_objection(this, "single transfer test done");
    endtask : run_phase

endclass : ahb_single_transfer_test

`endif // AHB_SINGLE_TRANSFER_TEST_INCLUDED_